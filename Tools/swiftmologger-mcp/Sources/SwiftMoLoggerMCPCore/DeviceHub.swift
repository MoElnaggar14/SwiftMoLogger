import Foundation
import SwiftMoLogger

/// What the Bonjour client reports about a device running LiveSink.
public enum DeviceEvent: Sendable, Equatable {
    case discovered(device: String)
    case connected(device: String)
    case line(device: String, data: Data)
    case disconnected(device: String)
    case gone(device: String)
}

/// A device as the agent sees it.
public struct DeviceSummary: Sendable, Equatable, Codable {
    public enum State: String, Sendable, Codable {
        case discovered, connected, reconnecting, gone
    }

    public let device: String
    public let state: State
    public let app: String?
    public let appVersion: String?
    public let os: String?
    public let protocolVersion: Int?
    public let sessions: Int
    public let buffered: Int
    public let lastEntryAt: Date?
}

/// A matching page of entries, oldest first.
public struct SearchResult: Sendable, Equatable {
    public let entries: [StoredEntry]
    /// Pass as `after_seq` to fetch only newer entries.
    public let nextSeq: UInt64?
    /// `true` when more entries matched than `limit`; the newest ones are returned.
    public let truncated: Bool
}

/// One HTTP exchange reconstructed from `NetworkLogger`'s entries.
public struct NetworkRequest: Sendable, Equatable, Codable {
    public let seq: UInt64
    public let device: String
    public let timestamp: Date
    public let method: String
    public let url: String
    public let status: Int?
    public let durationMS: Double?
    public let responseBytes: Int?
    public let error: String?

    public var failed: Bool { error != nil || (status ?? 0) >= 400 }
}

/// Owns every device, its buffered entries and the pending `wait_for` calls.
///
/// All state lives in this actor; queries are synchronous scans under its isolation.
public actor DeviceHub {
    private struct Device {
        var state: DeviceSummary.State = .discovered
        var hello: Hello?
        var sessions = 0
        var buffer: RingBuffer<StoredEntry>
        var lastEntryAt: Date?
    }

    private struct Waiter {
        let query: LogQuery
        let continuation: CheckedContinuation<StoredEntry?, Never>
    }

    private let capacityPerDevice: Int
    private let redactor: Redactor?
    private let allowedApps: Set<String>?
    private var devices: [String: Device] = [:]
    private var waiters: [UUID: Waiter] = [:]
    private var lastSeq: UInt64 = 0

    /// - Parameters:
    ///   - capacityPerDevice: Entries kept per device. The oldest are dropped first.
    ///   - redactor: Applied to every entry before it's stored, so nothing unredacted reaches the agent.
    ///     `nil` stores entries as the device sent them.
    ///   - allowedApps: When set, only devices whose service name (the app's bundle identifier) is listed are kept.
    public init(capacityPerDevice: Int = 10_000, redactor: Redactor? = Redactor(), allowedApps: Set<String>? = nil) {
        self.capacityPerDevice = capacityPerDevice
        self.redactor = redactor
        self.allowedApps = allowedApps
    }

    // MARK: - Events

    public func handle(_ event: DeviceEvent, now: Date = Date()) {
        switch event {
        case let .discovered(name):
            guard isAllowed(name) else { return }
            if devices[name] == nil {
                devices[name] = Device(buffer: RingBuffer(capacity: capacityPerDevice))
            } else if devices[name]?.state == .gone {
                devices[name]?.state = .discovered
            }
        case let .connected(name):
            guard isAllowed(name) else { return }
            if devices[name] == nil { handle(.discovered(device: name), now: now) }
            devices[name]?.state = .connected
            devices[name]?.sessions += 1
        case let .line(name, data):
            guard devices[name] != nil else { return }
            ingest(WireLine.decode(data), from: name, now: now)
        case let .disconnected(name):
            if devices[name]?.state == .connected { devices[name]?.state = .reconnecting }
        case let .gone(name):
            devices[name]?.state = .gone
        }
    }

    private func isAllowed(_ name: String) -> Bool {
        guard let allowedApps else { return true }
        // Bonjour renames duplicates "com.acme.shop (2)".
        let base = name.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
        return allowedApps.contains(base)
    }

    private func ingest(_ line: WireLine, from name: String, now: Date) {
        switch line {
        case let .hello(hello):
            devices[name]?.hello = hello
        case let .entry(entry):
            lastSeq += 1
            let stored = StoredEntry(
                seq: lastSeq,
                device: name,
                session: devices[name]?.sessions ?? 0,
                receivedAt: now,
                entry: redacted(entry)
            )
            devices[name]?.buffer.append(stored)
            devices[name]?.lastEntryAt = entry.timestamp
            resolveWaiters(with: stored)
        case .unknownControl, .invalid:
            break
        }
    }

    private func redacted(_ entry: LogEntry) -> LogEntry {
        guard let redactor else { return entry }
        return LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: redactor.redact(entry.message).output,
            tag: entry.tag,
            metadata: redactor.redact(entry.metadata),
            source: entry.source,
            threadName: entry.threadName,
            taskName: entry.taskName
        )
    }

    // MARK: - Queries

    public func devicesSummary() -> [DeviceSummary] {
        devices.map { name, device in
            DeviceSummary(
                device: name,
                state: device.state,
                app: device.hello?.app,
                appVersion: device.hello?.appVersion,
                os: device.hello?.os,
                protocolVersion: device.hello?.version,
                sessions: device.sessions,
                buffered: device.buffer.count,
                lastEntryAt: device.lastEntryAt
            )
        }
        .sorted { $0.device < $1.device }
    }

    public func search(_ query: LogQuery) -> SearchResult {
        let matching = allEntries(for: query.device).filter(query.matches)
        let page = Array(matching.suffix(query.limit))
        return SearchResult(entries: page, nextSeq: page.last?.seq ?? query.afterSeq, truncated: matching.count > page.count)
    }

    /// The entry with `id`, plus up to `context` entries before and after it on the same device.
    public func entry(id: UUID, context: Int = 0) -> (entry: StoredEntry, before: [StoredEntry], after: [StoredEntry])? {
        for device in devices.values {
            let entries = device.buffer.elements
            guard let index = entries.firstIndex(where: { $0.entry.id == id }) else { continue }
            let count = min(max(context, 0), 50)
            let before = Array(entries[max(0, index - count)..<index])
            let after = Array(entries[(index + 1)..<min(entries.count, index + 1 + count)])
            return (entries[index], before, after)
        }
        return nil
    }

    public func networkRequests(device: String? = nil, since: Date? = nil, failedOnly: Bool = false, limit: Int = 50) -> [NetworkRequest] {
        let requests = allEntries(for: device).compactMap { stored -> NetworkRequest? in
            let entry = stored.entry
            guard entry.message == "HTTP response" || entry.message == "HTTP failure",
                  case let .string(url)? = entry.metadata["http.url"] else { return nil }
            if let since, entry.timestamp < since { return nil }
            let request = NetworkRequest(
                seq: stored.seq,
                device: stored.device,
                timestamp: entry.timestamp,
                method: entry.metadata["http.method"].flatMap(Self.string) ?? "GET",
                url: url,
                status: entry.metadata["http.status"].flatMap(Self.int),
                durationMS: entry.metadata["http.duration_ms"].flatMap(Self.double),
                responseBytes: entry.metadata["http.response_bytes"].flatMap(Self.int),
                error: entry.metadata["error"].flatMap(Self.string)
            )
            return failedOnly && !request.failed ? nil : request
        }
        return Array(requests.suffix(min(max(limit, 1), 500)))
    }

    /// Waits for the next entry matching `query`, or returns `nil` after `timeout`.
    /// Only entries that arrive after the call count.
    public func waitFor(_ query: LogQuery, timeout: Duration) async -> StoredEntry? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<StoredEntry?, Never>) in
                waiters[id] = Waiter(query: query, continuation: continuation)
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.expire(id)
                }
            }
        } onCancel: {
            Task { await self.expire(id) }
        }
    }

    private func expire(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(returning: nil)
    }

    private func resolveWaiters(with stored: StoredEntry) {
        for (id, waiter) in waiters where waiter.query.matches(stored) {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume(returning: stored)
        }
    }

    private func allEntries(for device: String?) -> [StoredEntry] {
        if let device { return devices[device]?.buffer.elements ?? [] }
        return devices.values.flatMap(\.buffer.elements).sorted { $0.seq < $1.seq }
    }

    private static func string(_ value: LogMetadataValue) -> String? {
        if case let .string(string) = value { return string }
        return nil
    }

    private static func int(_ value: LogMetadataValue) -> Int? {
        switch value {
        case let .int(int): Int(int)
        case let .double(double): Int(double)
        default: nil
        }
    }

    private static func double(_ value: LogMetadataValue) -> Double? {
        switch value {
        case let .double(double): double
        case let .int(int): Double(int)
        default: nil
        }
    }
}
