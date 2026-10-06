import Foundation

/// Reads values out of MetricKit's JSON.
///
/// MetricKit writes measurements as formatted strings with a unit, such as
/// `"1,300 kB"`, `"20 sec"` or `"200 ms"`, so durations are converted to
/// milliseconds and sizes to bytes here. A bare number is taken to already be
/// in milliseconds or bytes.
enum MetricKitJSON {
    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Follows `path` through nested dictionaries.
    static func value(_ object: [String: Any]?, _ path: String...) -> Any? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    /// The first key in `keys` that `object` has a value for.
    static func first(_ object: [String: Any]?, _ keys: [String]) -> Any? {
        for key in keys {
            if let value = object?[key] { return value }
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.isEmpty ? nil : string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(exactly: double.rounded())
        }
        if let string = value as? String {
            return quantity(string).flatMap { Int(exactly: $0.value.rounded()) }
        }
        return nil
    }

    static func milliseconds(_ value: Any?) -> Double? {
        measurement(value, scales: durationScales)
    }

    static func bytes(_ value: Any?) -> Double? {
        measurement(value, scales: storageScales)
    }

    // MARK: - Measurements

    private static let durationScales: [String: Double] = [
        "": 1, "ms": 1, "msec": 1, "millisecond": 1, "milliseconds": 1,
        "us": 0.001,
        "s": 1_000, "sec": 1_000, "secs": 1_000, "second": 1_000, "seconds": 1_000,
        "min": 60_000, "mins": 60_000, "minute": 60_000, "minutes": 60_000,
        "h": 3_600_000, "hr": 3_600_000, "hrs": 3_600_000, "hour": 3_600_000, "hours": 3_600_000
    ]

    // MetricKit uses decimal units (UnitInformationStorage): 1 kB is 1,000 bytes.
    private static let storageScales: [String: Double] = [
        "": 1, "b": 1, "byte": 1, "bytes": 1,
        "kb": 1_000, "mb": 1_000_000, "gb": 1_000_000_000, "tb": 1_000_000_000_000,
        "kib": 1_024, "mib": 1_048_576, "gib": 1_073_741_824
    ]

    private static func measurement(_ value: Any?, scales: [String: Double]) -> Double? {
        if let text = value as? String {
            guard let parsed = quantity(text), let scale = scales[parsed.unit.lowercased()] else {
                return nil
            }
            return parsed.value * scale
        }
        return value as? Double
    }

    /// Splits `"1,300 kB"` into `(1300, "kB")`.
    static func quantity(_ text: String) -> (value: Double, unit: String)? {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var numberText = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isASCII, character.isNumber || ".,-+".contains(character) {
                numberText.append(character)
            } else if character.isWhitespace, !numberText.isEmpty,
                      index + 1 < characters.count,
                      characters[index + 1].isASCII, characters[index + 1].isNumber {
                // A grouping space, as in "1 300 kB".
            } else {
                break
            }
            index += 1
        }
        guard let value = number(from: numberText) else { return nil }
        let unit = String(characters[index...]).trimmingCharacters(in: .whitespaces)
        return (value, unit)
    }

    /// Parses a number written with either `,` or `.` as the grouping separator.
    private static func number(from text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        let normalized: String
        switch (text.lastIndex(of: "."), text.lastIndex(of: ",")) {
        case let (dot?, comma?):
            // Whichever separator comes last is the decimal one: "1,300.5" or "1.300,5".
            normalized = dot > comma
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        case let (nil, comma?):
            // "1,300" and "1,300,000" group thousands; "1,5" is a decimal comma.
            let isGrouping = text.filter { $0 == "," }.count > 1
                || text[text.index(after: comma)...].count == 3
            normalized = isGrouping
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ",", with: ".")
        case (.some, nil):
            normalized = text.filter { $0 == "." }.count > 1
                ? text.replacingOccurrences(of: ".", with: "")
                : text
        case (nil, nil):
            normalized = text
        }
        return Double(normalized)
    }
}
