#!/usr/bin/env python3
"""Audit an app's SwiftMoLogger usage: 3.x calls to migrate and release-safety issues.

Usage: audit_logging.py [PROJECT_ROOT]

Prints one line per finding as path:line: [kind] message, where kind is
  migrate  a 3.x API that doesn't exist in 4.0, with its replacement
  release  something that can leak logs or secrets in a release build
  note     worth a look, not necessarily wrong
Exit status: 1 if any migrate or release finding, else 0. Standard library only.
"""
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


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    findings = []
    uses_live_sink = False

    for path in walk(root, {".swift"}):
        rel = path.relative_to(root)
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
          f"{sum(f[2] == 'note' for f in findings)} note")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
