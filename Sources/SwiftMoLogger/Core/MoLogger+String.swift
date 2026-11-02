import Foundation

// swiftlint:disable line_length

// The `String` overloads of the level methods, kept only to explain the 5.0
// change: a `String` value is computed text, so the call site decides once
// whether it's shown. A string literal resolves to the `LogMessage` overloads,
// because the type checker ranks an unavailable overload below every available
// one. Calling one of these is a compile error, never a run-time trap.
public extension MoLogger {
    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func trace(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func debug(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func info(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func notice(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func warning(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func error(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func critical(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }

    @available(*, unavailable, message: "Log messages are private by default. Pass \"\\(text)\" to hide the text, or LogMessage(verbatim: text) to show it.")
    func fault(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        fatalError("Unavailable: log messages are LogMessage values")
    }
}
// swiftlint:enable line_length
