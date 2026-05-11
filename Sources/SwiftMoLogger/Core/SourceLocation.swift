import Foundation

/// Captures `#file`, `#function`, `#line`, and `#column` so log entries point
/// back to the exact call-site that produced them.
public struct SourceLocation: Sendable, Hashable, Codable, CustomStringConvertible {
    public let file: String
    public let function: String
    public let line: Int
    public let column: Int

    public init(file: String = #fileID, function: String = #function, line: Int = #line, column: Int = #column) {
        self.file = file
        self.function = function
        self.line = line
        self.column = column
    }

    /// Filename without module prefix (`Module/File.swift` → `File.swift`).
    public var fileName: String {
        guard let lastSlash = file.lastIndex(of: "/") else { return file }
        return String(file[file.index(after: lastSlash)...])
    }

    public var description: String {
        "\(fileName):\(line) \(function)"
    }
}
