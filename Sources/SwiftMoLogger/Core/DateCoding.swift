import Foundation

private let fractionalSecondsStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let wholeSecondsStyle = Date.ISO8601FormatStyle()

public extension JSONEncoder.DateEncodingStrategy {
    /// ISO 8601 with millisecond precision (`2026-10-04T12:00:00.123Z`).
    ///
    /// The built-in `.iso8601` strategy drops fractional seconds, so entries
    /// logged within the same second lose their order once persisted.
    static var iso8601WithFractionalSeconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsStyle.format(date))
        }
    }
}

public extension JSONDecoder.DateDecodingStrategy {
    /// ISO 8601 with or without fractional seconds, so files written by older
    /// versions (whole seconds) still decode.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: fractionalSecondsStyle) {
                return date
            }
            if let date = try? Date(string, strategy: wholeSecondsStyle) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date, got \(string)"
            )
        }
    }
}
