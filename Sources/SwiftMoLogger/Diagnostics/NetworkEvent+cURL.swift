import Foundation

public extension NetworkEvent {
    /// The exchange as a `curl` command you can paste into a terminal.
    ///
    /// It's built from what the event recorded, so the URL and header values
    /// are the redacted ones (a redacted `Authorization` header reads
    /// `[REDACTED]`), and the body is the captured, redacted body, if any.
    /// Every argument is single-quoted for POSIX shells. A truncated body is
    /// flagged with a trailing shell comment, because replaying it sends less
    /// than the app did.
    var curlCommand: String {
        var lines = ["curl"]
        if method.uppercased() != "GET" || requestBody != nil {
            lines.append("-X \(Self.shellQuoted(method))")
        }
        for (name, value) in (requestHeaders ?? [:]).sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            lines.append("-H \(Self.shellQuoted("\(name): \(value)"))")
        }
        if let body = requestBody {
            var data = "--data-raw \(Self.shellQuoted(body.text))"
            if body.isTruncated { data += " # request body truncated" }
            lines.append(data)
        }
        lines.insert(Self.shellQuoted(url.absoluteString), at: 1)
        return lines.joined(separator: " \\\n  ")
    }

    /// Wraps `value` in single quotes, closing and reopening them around each
    /// embedded quote (`'` becomes `'\''`). Nothing inside single quotes is
    /// expanded by a POSIX shell.
    internal static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
