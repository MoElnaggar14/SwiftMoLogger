#!/usr/bin/env python3
"""Audit an app's SwiftMoLogger usage: 3.x calls to migrate and release-safety issues.

Usage: audit_logging.py [--privacy | --fix-privacy] [PROJECT_ROOT]

Prints one line per finding as path:line: [kind] message, where kind is
  migrate  a 3.x API that doesn't exist in 4.0, with its replacement
  release  something that can leak logs or secrets in a release build
  note     worth a look, not necessarily wrong
  privacy  (with --privacy) an interpolation in a log message without privacy:,
           which renders <private> in 5.0 unless its type is numeric, Bool or
           LogPublicValue
--fix-privacy also adds `privacy: .public` to the interpolations that are safe to
show (`.rawValue`, names ending in count, Count, index, Index, ID or Id) and lists the rest.
Exit status: 1 if any migrate or release finding, else 0. privacy findings don't
change it. Standard library only.
"""
import argparse
import re
import sys
from pathlib import Path

SKIP_DIRS = {".build", "build", "DerivedData", "Pods", "Carthage", ".git", "SourcePackages", "checkouts"}

MIGRATIONS = [
    (r"\bSwiftMoLogger\.(info|notice|error|critical|fault|trace|debug)\s*\(", "inject a MoLogger and call logger.{0}(…)"),
    (r"\bSwiftMoLogger\.warn\s*\(", "logger.warning(…)"),
    (r"\bSwiftMoLogger\.log\s*\(", "logger.log(level, …)"),
    (r"\bSwiftMoLogger\.crash\s*\(", "logger.critical(…, tag: .crash)"),
    (r"\bMoLogger\.shared\b", "environment.logger (inject it)"),
    (r"\bEngineRegistry\.shared\b", "environment.registry"),
    (r"\bSwiftMoLogger\.(addEngine|removeEngine|allEngines|engineCount|minimumLevel|reset|enableRedaction)\b", "environment.registry.{0}"),
    (r"\bSwiftMoLogger\.withContext\b", "LogContext.with(…) { … }"),
    (r"\bSwiftMoLogger\.currentContext\b", "LogContext.current"),
    (r"\bSwiftMoLogger\.withTrace\b", "traceContext.run { … }"),
    (r"\bSwiftMoLogger\.breadcrumb\s*\(", "environment.breadcrumbs.record(…)"),
    (r"\bSwiftMoLogger\.breadcrumbs\s*\(", "environment.breadcrumbs.snapshot()"),
    (r"\bSwiftMoLogger\.clearBreadcrumbs\s*\(", "environment.breadcrumbs.clear()"),
    (r"\bSwiftMoLogger\.stream\s*\(", "environment.stream.subscribe(bufferSize:)"),
    (r"\bSwiftMoLogger\.publisher\s*\(", "let c = CombineLogPublisher(); registry.addEngine(c); c.publisher"),
    (r"\bSwiftMoLogger\.installRecorder\s*\(", "let (logging, logs) = LogEnvironment.recording() or MoLogger.recording()"),
    (r"\bLogSignpost\.", "environment.signposter (measure / measureAsync / makeInterval / event)"),
    (r":\s*[^{]*\bLogTagged\b", "drop LogTagged; store logger.with(tag:) and call it"),
    (r"\bAppVitalsMonitor\.shared\b", "AppVitalsMonitor(logger:history:)"),
    (r"\bMetricKitCrashReporter\s*\(\s*\)", "MetricKitCrashReporter(logger:)"),
    (r"\bNetworkLogger\.install(OnSharedSession)?\s*\(", "URLSession(configuration:delegate: NetworkLogger(environment:), delegateQueue:)"),
    (r"\.excludeFromNetworkLogging\s*\(", "remove: only sessions given a NetworkLogger are logged"),
    (r"#log\s*\(\s*\"", "#log(logger, \"…\")"),
    (r"#measure\s*\(\s*\"", "#measure(signposter, \"…\") { … }"),
    (r"\bLiveSink\s*\(\s*\)", "LiveSink(statusLogger: logging.logger)"),
    (r"\bDiagnosticsHubView\s*\(\s*\)", "DiagnosticsHubView(environment:)"),
    (r"\bHubViewModel\s*\(\s*\)", "HubViewModel(environment:)"),
    (r"\bLogConsoleView\s*\(\s*\)", "LogConsoleView(stream: environment.stream)"),
    (r"\bLogConsoleViewModel\s*\(\s*\)", "LogConsoleViewModel(stream:)"),
    (r"\bFlightRecorder\s*\(\s*fileURL:", "FlightRecorder(environment:fileURL:…)"),
    (r"\bFlightRecorder\s*\(\s*\)", "FlightRecorder(environment:)"),
    (r"\bBugReporter\s*\(\s*memoryEngine:", "BugReporter(environment:memoryEngine:vitalsMonitor:appName:)"),
    (r"\bSwiftMoLogHandler\.bootstrap\s*\(\s*\)", "SwiftMoLogHandler.bootstrap(logger:)"),
    (r"\bSwiftMoLogHandler\s*\(\s*label:[^,()]*\)", "SwiftMoLogHandler(label:logger:)"),
]
MIGRATIONS = [(re.compile(p), r) for p, r in MIGRATIONS]


def walk(root, suffixes):
    for path in root.rglob("*"):
        if path.is_file() and path.suffix in suffixes and not any(p in SKIP_DIRS for p in path.parts):
            yield path


def debug_only_lines(lines):
    """Per line: True when it sits inside a DEBUG-only branch (best effort, no expression parsing)."""
    stack, result = [], []  # each entry: [kind, active] with kind "debug", "release" or "other"
    for line in lines:
        s = line.strip().replace(" ", "")
        if s.startswith("#if"):
            kind = "release" if s == "#if!DEBUG" else "debug" if s.startswith("#ifDEBUG") else "other"
            stack.append([kind, kind == "debug"])
        elif s.startswith("#elseif") and stack:
            stack[-1][1] = False
        elif s.startswith("#else") and stack:
            stack[-1][1] = stack[-1][0] == "release"
        elif s.startswith("#endif") and stack:
            stack.pop()
        result.append(any(active for _, active in stack))
    return result


# MARK: - Privacy (5.0 makes unmarked interpolations private)

LOG_CALL = re.compile(r"(?:\.\s*(?:trace|debug|info|notice|warning|error|critical|fault|log)|#log)\s*\(")
NUMERIC = re.compile(r"^-?\d[\d_]*(?:\.\d+)?$|\.count$")
SAFE_TO_SHOW = re.compile(r"^[A-Za-z_][\w.]*(?:\.rawValue|count|Count|index|Index|ID|Id)$")
PRIVACY_HINT = "renders <private> in 5.0: add privacy: .public if it's safe, or privacy: .private to keep it hidden"


def scan_swift(text):
    """Classifies every character of `text` as code, string text or comment.

    Returns (kinds, interpolations): kinds[i] is "c", "s" or "m", and each
    interpolation is (start, end, depth) for the expression between `\\(` and its
    `)`, depth counting the interpolations around it. The `\\(` and `)` themselves
    are string text, so counting parentheses in code skips them. Best effort: no
    regex literals, no `#if` evaluation.
    """
    kinds = ["c"] * len(text)
    interpolations = []
    n = len(text)

    def code(i, depth, closing):
        """Scans code from i to the `)` that closes an interpolation (or the end)."""
        parens = 0
        while i < n:
            ch = text[i]
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end < 0 else end
                kinds[i:end] = ["m"] * (end - i)
                i = end
            elif text.startswith("/*", i):
                end = text.find("*/", i + 2)
                end = n if end < 0 else end + 2
                kinds[i:end] = ["m"] * (end - i)
                i = end
            elif ch == '"' or (ch == "#" and re.match(r"#+\"", text[i:i + 8])):
                i = string(i, depth)
            elif ch == "(":
                parens += 1
                i += 1
            elif ch == ")":
                if closing and parens == 0:
                    return i
                parens -= 1
                i += 1
            else:
                i += 1
        return n

    def string(i, depth):
        """Scans a string literal starting at its opening delimiter; returns the index after it."""
        start = i
        while text[i] == "#":
            i += 1
        hashes = i - start
        quote = '"""' if text.startswith('"""', i) else '"'
        close = quote + "#" * hashes
        escape = "\\" + "#" * hashes
        i += len(quote)
        kinds[start:i] = ["s"] * (i - start)
        while i < n:
            if text.startswith(close, i):
                kinds[i:i + len(close)] = ["s"] * len(close)
                return i + len(close)
            if text.startswith(escape + "(", i):
                begin = i + len(escape) + 1
                kinds[i:begin] = ["s"] * (begin - i)
                end = code(begin, depth + 1, closing=True)
                interpolations.append((begin, end, depth + 1))
                if end < n:
                    kinds[end] = "s"
                i = end + 1
            elif text.startswith(escape, i):
                kinds[i:i + len(escape) + 1] = ["s"] * (len(escape) + 1)
                i += len(escape) + 1
            elif quote == '"' and text[i] == "\n":
                return i  # unterminated: stop at the end of the line
            else:
                kinds[i] = "s"
                i += 1
        return n

    code(0, 0, closing=False)
    return kinds, interpolations


def message_interpolations(text, kinds, interpolations):
    """The top-level interpolations in the unlabelled arguments of each log call."""
    nesting = [0] * (len(text) + 1)  # how many interpolations each character is in
    for start, end, _ in interpolations:
        nesting[start] += 1
        nesting[end] -= 1
    for i in range(1, len(nesting)):
        nesting[i] += nesting[i - 1]
    found = []
    for match in LOG_CALL.finditer(text):
        if kinds[match.start()] != "c":
            continue
        depth = nesting[match.start()]
        open_paren = match.end() - 1
        # Split the arguments at top-level commas, skipping strings, comments and interpolations.
        level, i, args, arg_start = 0, open_paren + 1, [], open_paren + 1
        while i < len(text):
            if kinds[i] == "c" and nesting[i] == depth:
                ch = text[i]
                if ch in "([{":
                    level += 1
                elif ch in ")]}":
                    if level == 0:
                        break
                    level -= 1
                elif ch == "," and level == 0:
                    args.append((arg_start, i))
                    arg_start = i + 1
            i += 1
        args.append((arg_start, i))
        for start, end in args:
            if re.match(r"\s*\w+\s*:(?!:)", text[start:end]):
                continue  # labelled: tag:, metadata:, file: …
            for s, e, d in interpolations:
                if start <= s < end and d == depth + 1:
                    found.append((s, e))
    return sorted(set(found))


def privacy_findings(text):
    """(line, expression, start, end) for each unmarked, possibly non-numeric interpolation."""
    kinds, interpolations = scan_swift(text)
    results = []
    for start, end in message_interpolations(text, kinds, interpolations):
        expression = text[start:end].strip()
        if re.search(r",\s*privacy\s*:", expression) or NUMERIC.search(expression):
            continue
        results.append((text.count("\n", 0, start) + 1, expression, start, end))
    return results


def main():
    parser = argparse.ArgumentParser(description="Audit an app's SwiftMoLogger usage.")
    parser.add_argument("root", nargs="?", default=".", help="project root (default: current directory)")
    parser.add_argument("--privacy", action="store_true",
                        help="list interpolations in log messages without privacy: (they render <private> in 5.0)")
    parser.add_argument("--fix-privacy", action="store_true",
                        help="mark the safe ones privacy: .public in place, then list the rest")
    options = parser.parse_args()
    root = Path(options.root).resolve()
    findings = []
    uses_live_sink = False
    fixed = 0

    for path in walk(root, {".swift"}):
        rel = path.relative_to(root)
        if options.privacy or options.fix_privacy:
            text = path.read_text(errors="ignore")
            unmarked = privacy_findings(text)
            if options.fix_privacy:
                safe = [f for f in unmarked if SAFE_TO_SHOW.match(f[1])]
                for _, _, start, end in sorted(safe, key=lambda f: f[2], reverse=True):
                    body = text[start:end].rstrip()
                    text = text[:start] + body + ", privacy: .public" + text[start + len(body):]
                if safe:
                    path.write_text(text)
                    fixed += len(safe)
                    unmarked = privacy_findings(text)
            for number, expression, _, _ in unmarked:
                expression = " ".join(expression.split())
                findings.append((rel, number, "privacy", f"\\({expression}) {PRIVACY_HINT}"))
        lines = path.read_text(errors="ignore").splitlines()
        in_debug = debug_only_lines(lines)
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            for pattern, replacement in MIGRATIONS:
                match = pattern.search(code)
                if match:
                    hint = replacement.format(*match.groups()) if match.groups() else replacement
                    findings.append((rel, number, "migrate", f"{match.group(0).strip()} → {hint}"))
            if re.search(r"\bLiveSink\s*\(", code):
                uses_live_sink = True
                if not in_debug[number - 1]:
                    findings.append((rel, number, "note", "LiveSink outside #if DEBUG: start() refuses in release, but keeping it debug-only keeps the listener code out of the binary"))
                if "allowInRelease: true" in code:
                    findings.append((rel, number, "release", "LiveSink(allowInRelease: true): only for internal QA builds"))
            if re.search(r"\bDatadogLogEngine\s*\(\s*apiKey:\s*\"", code):
                findings.append((rel, number, "release", "hard-coded Datadog API key ships in the binary; proxy through your backend with HTTPLogShipper"))
            if re.search(r"urlRedaction:\s*\.full\b", code) and not in_debug[number - 1]:
                findings.append((rel, number, "release", "URLRedaction.full logs URLs with secrets; keep it to debug builds"))
            if re.search(r"\brevealsPrivateValues\s*=\s*true\b", code) and not in_debug[number - 1]:
                findings.append((rel, number, "release", "revealsPrivateValues = true sends .private values to every engine; keep it inside #if DEBUG"))
            if re.search(r"\bSystemLogger\s*\([^)]*privacy:\s*\.public", code):
                findings.append((rel, number, "note", "SystemLogger(privacy: .public) makes messages readable in sysdiagnose"))
            if re.search(r"try!\s*FileLogEngine\s*\(", code):
                findings.append((rel, number, "note", "try! FileLogEngine traps at launch if the file can't be opened; use try? and wrap it in RedactingLogEngine"))
            if re.search(r"\bFlightRecorder\s*\(\s*environment:", code) and "redactor:" not in code:
                findings.append((rel, number, "note", "FlightRecorder without redactor: writes raw entries to disk"))
            if re.search(r"^\s*(?:public\s+|private\s+|fileprivate\s+)?(?:let|var)\s+\w+\s*=\s*LogEnvironment\s*\(", line) and line == line.lstrip():
                findings.append((rel, number, "note", "top-level LogEnvironment is a global; create it at the composition root and inject it"))

    if uses_live_sink:
        config = "".join(p.read_text(errors="ignore") for p in walk(root, {".plist", ".pbxproj", ".xcconfig"}))
        for key in ("NSLocalNetworkUsageDescription", "_swiftmologger._tcp"):
            if key not in config:
                findings.append((Path("Info.plist"), 0, "note",
                                 f"LiveSink is used but {key} isn't declared; the listener fails on a real device"))

    for rel, number, kind, message in findings:
        print(f"{rel}:{number}: [{kind}] {message}")
    blocking = [f for f in findings if f[2] in ("migrate", "release")]
    print(f"\n{len(findings)} finding(s): "
          f"{sum(f[2] == 'migrate' for f in findings)} migrate, "
          f"{sum(f[2] == 'release' for f in findings)} release, "
          f"{sum(f[2] == 'note' for f in findings)} note"
          + (f", {sum(f[2] == 'privacy' for f in findings)} privacy" if options.privacy or options.fix_privacy else ""))
    if options.fix_privacy:
        print(f"Marked {fixed} interpolation(s) privacy: .public.")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
