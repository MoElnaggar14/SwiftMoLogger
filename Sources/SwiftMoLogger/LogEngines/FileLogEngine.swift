import Foundation

/// JSON-Lines file backend with size-based rotation.
///
/// Each entry is encoded as a single-line JSON object so the log file is
/// directly tail-able and consumable by analytics pipelines. Writes happen on
/// a dedicated serial queue; the caller of ``log(_:)`` never blocks on I/O.
///
/// The backlog of entries waiting to be written is capped at
/// ``maxPendingEntries``, so a burst of logging can't grow memory without
/// bound. Entries over the cap are dropped and counted, and one warning line
/// in the file records how many were lost.
///
/// Rotation is triggered when the active file exceeds ``maxFileSizeBytes``.
/// The current file is renamed to `<name>.1`, older numbered files shift
/// down, and the oldest beyond ``maxRotatedFiles`` is deleted.
///
/// Log files can hold personal data even with redaction on, so every file is
/// created with ``protection`` (see ``Protection``).
public final class FileLogEngine: LogEngine, @unchecked Sendable {
    /// How log files are encrypted at rest on iOS, tvOS, watchOS and visionOS.
    /// Ignored on macOS, which has no per-file data protection.
    public enum Protection: Sendable, Equatable {
        /// Readable whenever the device is on. Only for logs with nothing personal in them.
        case unprotected
        /// Encrypted from boot until the first unlock. The iOS default for app files;
        /// background logging keeps working.
        case completeUntilFirstUserAuthentication
        /// Open files stay writable while the device is locked and new files can still be
        /// created (so rotation works), but nothing can be read back until it's unlocked.
        /// The strongest class that keeps background logging working.
        case completeUnlessOpen
        /// Encrypted whenever the device is locked. Writes fail while it's locked, so only
        /// for apps that never log in the background.
        case complete
    }

    public let engineID: String
    public let minimumLevel: LogLevel

    public let fileURL: URL
    public let maxFileSizeBytes: Int
    public let maxRotatedFiles: Int
    /// Most entries that may wait to be written before new ones are dropped.
    public let maxPendingEntries: Int
    /// The data-protection class of every log file, including rotated ones.
    public let protection: Protection

    private let queue: DispatchQueue
    private let backlogLock = UnfairLock()
    private var pendingCount = 0
    private var droppedSinceLastWrite = 0
    private var totalDropped = 0
    private let encoder: JSONEncoder
    private var handle: FileHandle?
    private var currentSize: Int = 0

    public init(
        fileURL: URL,
        maxFileSizeBytes: Int = 1_048_576,
        maxRotatedFiles: Int = 3,
        maxPendingEntries: Int = 10_000,
        protection: Protection = .completeUntilFirstUserAuthentication,
        minimumLevel: LogLevel = .info
    ) throws {
        self.fileURL = fileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxRotatedFiles = max(0, maxRotatedFiles)
        self.maxPendingEntries = max(1, maxPendingEntries)
        self.protection = protection
        self.minimumLevel = minimumLevel
        // Keyed by full path: two engines for the same file replace each other,
        // same-named files in different directories don't.
        self.engineID = "swiftmologger.file.\(fileURL.standardizedFileURL.path)"
        self.queue = DispatchQueue(label: "swiftmologger.file.\(fileURL.lastPathComponent)", qos: .utility)
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds

        try Self.ensureFileExists(at: fileURL, protection: protection)
        // A file written by an earlier version keeps its old class otherwise.
        Self.apply(protection, to: fileURL)
        self.handle = try Self.openForAppending(fileURL)
        self.currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    deinit {
        try? handle?.close()
    }

    public func log(_ entry: LogEntry) {
        let accepted: Bool = backlogLock.withLock {
            guard pendingCount < maxPendingEntries else {
                droppedSinceLastWrite += 1
                totalDropped += 1
                return false
            }
            pendingCount += 1
            return true
        }
        guard accepted else { return }
        // Strong capture on purpose: queued writes must land even if the
        // engine is removed from the registry before the queue drains.
        queue.async {
            let dropped: Int = self.backlogLock.withLock {
                self.pendingCount -= 1
                defer { self.droppedSinceLastWrite = 0 }
                return self.droppedSinceLastWrite
            }
            if dropped > 0 {
                self.writeEntry(LogEntry(
                    level: .warning,
                    message: "FileLogEngine dropped \(dropped) entries: more than \(self.maxPendingEntries) were waiting"
                ))
            }
            self.writeEntry(entry)
        }
    }

    /// How many entries were dropped because the backlog was full.
    public var droppedEntryCount: Int {
        backlogLock.withLock { totalDropped }
    }

    /// Synchronously flush any pending writes. Useful before bug reports or
    /// shutdown.
    public func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }

    /// Pauses and resumes the writer, so tests can fill the backlog deterministically.
    func suspendWrites() { queue.suspend() }
    func resumeWrites() { queue.resume() }

    /// All log files currently on disk for this engine (current + rotated).
    public func allLogFileURLs() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.lastPathComponent
        var urls: [URL] = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            urls.append(fileURL)
        }
        for index in stride(from: 1, through: maxRotatedFiles, by: 1) {
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
        try? handle?.close()
        handle = nil
        // Whatever happens while shifting files, reopen the active file so a
        // single failed rotation doesn't silently drop every later write.
        defer { reopenActiveFile() }

        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.lastPathComponent
        let manager = FileManager.default

        guard maxRotatedFiles > 0 else {
            try manager.removeItem(at: fileURL)
            return
        }
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
        if manager.fileExists(atPath: fileURL.path) {
            try manager.moveItem(at: fileURL, to: directory.appendingPathComponent("\(base).1"))
        }
    }

    private func reopenActiveFile() {
        do {
            try Self.ensureFileExists(at: fileURL, protection: protection)
            handle = try Self.openForAppending(fileURL)
            currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        } catch {
            NSLog("FileLogEngine could not reopen %@: %@", fileURL.path, String(describing: error))
        }
    }

    /// Opens with `O_APPEND`, so every write lands at the current end of the
    /// file even if another engine or process appends to it too.
    private static func openForAppending(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func ensureFileExists(at url: URL, protection: Protection) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil, attributes: protection.fileAttributes)
        }
    }

    /// Best effort: a file that can't be updated keeps working with its current class.
    private static func apply(_ protection: Protection, to url: URL) {
        let attributes = protection.fileAttributes
        guard !attributes.isEmpty else { return }
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

extension FileLogEngine.Protection {
    /// The attributes that apply this class to a file; empty on macOS.
    var fileAttributes: [FileAttributeKey: Any] {
        #if os(macOS)
        return [:]
        #else
        return [.protectionKey: fileProtectionType]
        #endif
    }

    #if !os(macOS)
    var fileProtectionType: FileProtectionType {
        switch self {
        case .unprotected: return .none
        case .completeUntilFirstUserAuthentication: return .completeUntilFirstUserAuthentication
        case .completeUnlessOpen: return .completeUnlessOpen
        case .complete: return .complete
        }
    }
    #endif
}
