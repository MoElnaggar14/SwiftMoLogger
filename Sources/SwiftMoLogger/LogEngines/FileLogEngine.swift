import Foundation

/// JSON-Lines file backend with size-based rotation.
///
/// Each entry is encoded as a single-line JSON object so the log file is
/// directly tail-able and consumable by analytics pipelines. Writes happen on
/// a dedicated serial queue; the caller of ``log(_:)`` never blocks on I/O.
///
/// Rotation is triggered when the active file exceeds ``maxFileSizeBytes``.
/// The current file is renamed to `<name>.1`, older numbered files shift
/// down, and the oldest beyond ``maxRotatedFiles`` is deleted.
public final class FileLogEngine: LogEngine, @unchecked Sendable {
    public let engineID: String
    public let minimumLevel: LogLevel

    public let fileURL: URL
    public let maxFileSizeBytes: Int
    public let maxRotatedFiles: Int

    private let queue: DispatchQueue
    private let encoder: JSONEncoder
    private var handle: FileHandle?
    private var currentSize: Int = 0

    public init(
        fileURL: URL,
        maxFileSizeBytes: Int = 1_048_576,
        maxRotatedFiles: Int = 3,
        minimumLevel: LogLevel = .info
    ) throws {
        self.fileURL = fileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxRotatedFiles = maxRotatedFiles
        self.minimumLevel = minimumLevel
        self.engineID = "swiftmologger.file.\(fileURL.lastPathComponent)"
        self.queue = DispatchQueue(label: "swiftmologger.file.\(fileURL.lastPathComponent)", qos: .utility)
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        try Self.ensureFileExists(at: fileURL)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        self.handle = handle
        self.currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    deinit {
        try? handle?.close()
    }

    public func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            self?.writeEntry(entry)
        }
    }

    /// Synchronously flush any pending writes. Useful before bug reports or
    /// shutdown.
    public func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }

    /// All log files currently on disk for this engine (current + rotated).
    public func allLogFileURLs() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.lastPathComponent
        var urls: [URL] = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            urls.append(fileURL)
        }
        for index in 1...maxRotatedFiles {
            let rotated = directory.appendingPathComponent("\(base).\(index)")
            if FileManager.default.fileExists(atPath: rotated.path) {
                urls.append(rotated)
            }
        }
        return urls
    }

    // MARK: - Private

    private func writeEntry(_ entry: LogEntry) {
        guard let handle = handle else { return }
        do {
            var data = try encoder.encode(entry)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            currentSize += data.count
            if currentSize >= maxFileSizeBytes {
                try rotate()
            }
        } catch {
            // Cannot use SwiftMoLogger here (would recurse). Fall back to
            // os.log so the error is still surfaced.
            NSLog("FileLogEngine write failed: %@", String(describing: error))
        }
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil

        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.lastPathComponent
        let manager = FileManager.default

        let oldest = directory.appendingPathComponent("\(base).\(maxRotatedFiles)")
        if manager.fileExists(atPath: oldest.path) {
            try manager.removeItem(at: oldest)
        }
        for index in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let from = directory.appendingPathComponent("\(base).\(index)")
            let to = directory.appendingPathComponent("\(base).\(index + 1)")
            if manager.fileExists(atPath: from.path) {
                try manager.moveItem(at: from, to: to)
            }
        }
        let rotated = directory.appendingPathComponent("\(base).1")
        if manager.fileExists(atPath: fileURL.path) {
            try manager.moveItem(at: fileURL, to: rotated)
        }
        try Self.ensureFileExists(at: fileURL)
        let newHandle = try FileHandle(forWritingTo: fileURL)
        try newHandle.seekToEnd()
        handle = newHandle
        currentSize = 0
    }

    private static func ensureFileExists(at url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
    }
}
