import Foundation

// MARK: - Core Protocol

/// Logging engine protocol - the foundation of SwiftMoLogger's extensible architecture
public protocol LogEngine {
    /// Log an informational message
    func info(message: String)

    /// Log a warning message
    func warn(message: String)

    /// Log an error message
    func error(message: String)
}

// MARK: - Thread-Safe Engine Registry

/// Thread-safe registry managing all logging engines
public final class EngineRegistry {
    public static let shared = EngineRegistry()

    private var engines: [LogEngine] = []
    private let queue = DispatchQueue(label: "swiftmologger.registry", qos: .utility, attributes: .concurrent)

    private init() {
        // Initialize with system logger
        engines.append(SystemLogger())
    }

    /// Add a custom logging engine
    public func addEngine(_ engine: LogEngine) {
        queue.async(flags: .barrier) {
            self.engines.append(engine)
        }
    }

    /// Remove engine at specified index (cannot remove system logger at index 0)
    public func removeEngine(at index: Int) {
        queue.async(flags: .barrier) {
            guard index > 0 && index < self.engines.count else { return }
            self.engines.remove(at: index)
        }
    }

    /// Get all registered engines (thread-safe)
    public func getAllEngines() -> [LogEngine] {
        queue.sync {
            Array(engines)
        }
    }

    /// Get count of all engines
    public var engineCount: Int {
        queue.sync {
            engines.count
        }
    }

    /// Clear all custom engines (keep system logger)
    public func reset() {
        queue.async(flags: .barrier) {
            self.engines = [SystemLogger()]
        }
    }
}
