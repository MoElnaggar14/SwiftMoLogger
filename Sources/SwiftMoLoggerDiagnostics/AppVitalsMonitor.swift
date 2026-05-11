import Foundation
import SwiftMoLogger
import Darwin
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Periodic snapshot of app runtime vitals (memory, CPU, FPS, thermal
/// state). Emits a log entry on every sample at `.notice`, so adopters can
/// see the curve on Console.app or pipe it to a backend via the remote
/// shipping engines.
///
/// ```swift
/// AppVitalsMonitor.shared.start(interval: 5)
/// ```
public final class AppVitalsMonitor: @unchecked Sendable {
    public static let shared = AppVitalsMonitor()

    public struct Sample: Sendable, Codable {
        public let timestamp: Date
        public let memoryUsedBytes: UInt64
        public let cpuUsagePercent: Double
        public let fps: Double
        public let thermalState: String
        public let batteryLevel: Double
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "swiftmologger.vitals", qos: .utility)
    private var lock = os_unfair_lock_s()
    private var _lastSample: Sample?

    #if canImport(QuartzCore) && (os(iOS) || os(tvOS))
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var fpsStart: CFTimeInterval = 0
    private var lastFPS: Double = 0
    #endif

    private init() {}

    public var lastSample: Sample? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _lastSample
    }

    public func start(interval: TimeInterval = 10) {
        stop()
        #if canImport(QuartzCore) && (os(iOS) || os(tvOS))
        DispatchQueue.main.async {
            self.fpsStart = CACurrentMediaTime()
            self.frameCount = 0
            self.displayLink = CADisplayLink(target: self, selector: #selector(self.tickFrame))
            self.displayLink?.add(to: .main, forMode: .common)
        }
        #endif

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sampleAndEmit()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        #if canImport(QuartzCore) && (os(iOS) || os(tvOS))
        displayLink?.invalidate()
        displayLink = nil
        #endif
    }

    // MARK: - Sampling

    private func sampleAndEmit() {
        let sample = Sample(
            timestamp: Date(),
            memoryUsedBytes: currentMemoryFootprint(),
            cpuUsagePercent: currentCPUUsage(),
            fps: currentFPS(),
            thermalState: thermalStateLabel(),
            batteryLevel: currentBatteryLevel()
        )
        os_unfair_lock_lock(&lock)
        _lastSample = sample
        os_unfair_lock_unlock(&lock)

        SwiftMoLogger.notice("vitals", tag: .performance, metadata: [
            "memory_mb": .double(Double(sample.memoryUsedBytes) / 1_048_576),
            "cpu_pct": .double(sample.cpuUsagePercent),
            "fps": .double(sample.fps),
            "thermal": .string(sample.thermalState),
            "battery": .double(sample.batteryLevel)
        ])
    }

    private func currentMemoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func currentCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }
        var total: Double = 0
        // Compute count from layout to avoid relying on the
        // THREAD_BASIC_INFO_COUNT C macro (not reliably imported).
        let infoCapacity = MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(infoCapacity)
            let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: infoCapacity) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        return total
    }

    private func currentFPS() -> Double {
        #if canImport(QuartzCore) && (os(iOS) || os(tvOS))
        var fps: Double = 0
        DispatchQueue.main.sync {
            let now = CACurrentMediaTime()
            let elapsed = now - self.fpsStart
            if elapsed > 0 {
                fps = Double(self.frameCount) / elapsed
            }
            self.frameCount = 0
            self.fpsStart = now
        }
        return fps
        #else
        return 0
        #endif
    }

    private func thermalStateLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func currentBatteryLevel() -> Double {
        #if canImport(UIKit) && os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Double(UIDevice.current.batteryLevel)
        #else
        return -1
        #endif
    }

    #if canImport(QuartzCore) && (os(iOS) || os(tvOS))
    @objc private func tickFrame() {
        frameCount += 1
    }
    #endif
}
