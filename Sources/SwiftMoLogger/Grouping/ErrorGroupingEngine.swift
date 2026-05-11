import Foundation

/// Aggregated record of one or more log entries that share a fingerprint.
public struct ErrorGroup: Sendable, Hashable, Codable, Identifiable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public let level: LogLevel
    public let exemplar: String       // representative message, with variable
                                      // bits replaced by placeholders
    public var firstSeen: Date
    public var lastSeen: Date
    public var count: Int
}

/// Decorator engine that groups noisy error/warning logs by fingerprint so
/// a 1 000-occurrence spam is rendered as a single card with `count = 1000`
/// instead of 1 000 individual rows in the Hub or in a remote backend.
///
/// Fingerprinting strategy:
/// 1. Take the message + tag domain.
/// 2. Replace digit runs with `#`, UUIDs with `<uuid>`, hex blobs with `<hex>`,
///    quoted strings with `"…"`.
/// 3. SHA-256 the result; take the first 16 hex chars as the fingerprint.
///
/// Filtering can be configured to skip lower severities — by default only
/// `.warning` and above are fingerprinted, everything else passes through.
public final class ErrorGroupingEngine: LogEngine, @unchecked Sendable {
    public let engineID: String
    public let minimumLevel: LogLevel

    private let wrapped: any LogEngine
    private let fingerprintMinLevel: LogLevel
    private let emitThreshold: Int
    private var lock = os_unfair_lock_s()
    private var groups: [String: ErrorGroup] = [:]

    /// - Parameters:
    ///   - wrapped: engine to forward entries to.
    ///   - fingerprintMinLevel: only entries at this level or higher are
    ///     fingerprinted. Lower-severity entries pass through unchanged.
    ///   - emitThreshold: forward the first `emitThreshold` occurrences of
    ///     each group, then drop further entries to the wrapped engine
    ///     while still bumping the count. `1` means "emit only the first,
    ///     remember the count for later via ``snapshot()``".
    public init(
        wrapping wrapped: any LogEngine,
        fingerprintMinLevel: LogLevel = .warning,
        emitThreshold: Int = 1
    ) {
        self.wrapped = wrapped
        self.fingerprintMinLevel = fingerprintMinLevel
        self.emitThreshold = max(emitThreshold, 1)
        self.engineID = "swiftmologger.grouping.\(wrapped.engineID)"
        self.minimumLevel = wrapped.minimumLevel
    }

    public func log(_ entry: LogEntry) {
        guard entry.level >= fingerprintMinLevel else {
            wrapped.log(entry)
            return
        }
        let fp = ErrorGroupingEngine.fingerprint(for: entry)
        let shouldForward: Bool
        os_unfair_lock_lock(&lock)
        if var existing = groups[fp] {
            existing.count += 1
            existing.lastSeen = entry.timestamp
            groups[fp] = existing
            shouldForward = existing.count <= emitThreshold
        } else {
            groups[fp] = ErrorGroup(
                fingerprint: fp,
                level: entry.level,
                exemplar: ErrorGroupingEngine.normalise(entry.message),
                firstSeen: entry.timestamp,
                lastSeen: entry.timestamp,
                count: 1
            )
            shouldForward = true
        }
        os_unfair_lock_unlock(&lock)
        if shouldForward {
            wrapped.log(entry)
        }
    }

    /// Snapshot of all observed groups, sorted by count descending.
    public func snapshot() -> [ErrorGroup] {
        os_unfair_lock_lock(&lock)
        let copy = groups
        os_unfair_lock_unlock(&lock)
        return copy.values.sorted { $0.count > $1.count }
    }

    public func clear() {
        os_unfair_lock_lock(&lock)
        groups.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Fingerprinting

    /// Stable 16-char hex fingerprint. Same algorithm used by the Hub UI
    /// so groups stay correlated across the boundary.
    public static func fingerprint(for entry: LogEntry) -> String {
        let normalised = normalise(entry.message) + "|" + (entry.tag?.domain ?? "-") + "|" + String(entry.level.rawValue)
        return sha256Hex(normalised, prefixBytes: 8)
    }

    /// Replace variable substrings so the same error shape collapses to
    /// one fingerprint.
    public static func normalise(_ message: String) -> String {
        var output = message
        // UUIDs → <uuid>
        output = output.replacingOccurrences(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            with: "<uuid>",
            options: .regularExpression
        )
        // Long hex strings (>= 12 chars) → <hex>
        output = output.replacingOccurrences(
            of: #"\b[0-9a-fA-F]{12,}\b"#,
            with: "<hex>",
            options: .regularExpression
        )
        // Quoted strings → "…"
        output = output.replacingOccurrences(
            of: #""[^"]*""#,
            with: #""…""#,
            options: .regularExpression
        )
        // Number runs → #
        output = output.replacingOccurrences(
            of: #"-?\d+(?:\.\d+)?"#,
            with: "#",
            options: .regularExpression
        )
        return output
    }

    private static func sha256Hex(_ input: String, prefixBytes: Int) -> String {
        let bytes = Array(input.utf8)
        let digest = SHA256.hash(bytes)
        let prefix = digest.prefix(prefixBytes)
        return prefix.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Minimal SHA-256 to avoid a CryptoKit import dance on non-Apple platforms.

/// Tiny FIPS 180-4 SHA-256. Not constant-time, only used for fingerprinting.
enum SHA256 {
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        var message = bytes
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> shift) & 0xff))
        }
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let base = chunkStart + index * 4
                w[index] = (UInt32(message[base]) << 24)
                    | (UInt32(message[base + 1]) << 16)
                    | (UInt32(message[base + 2]) << 8)
                    | UInt32(message[base + 3])
            }
            for index in 16..<64 {
                let s0 = rotr(w[index - 15], 7) ^ rotr(w[index - 15], 18) ^ (w[index - 15] >> 3)
                let s1 = rotr(w[index - 2], 17) ^ rotr(w[index - 2], 19) ^ (w[index - 2] >> 10)
                w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
            }
            var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3]
            var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7]
            for index in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[index] &+ w[index]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let mj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ mj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }

    private static func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
