import os

/// A heap-allocated `os_unfair_lock`.
///
/// `os_unfair_lock` must live at a stable address. Taking `&lock` on a stored
/// property doesn't guarantee one: Swift is free to pass a temporary copy, which
/// silently turns the lock into a no-op. Allocating it once and holding the
/// pointer gives the lock a fixed address for its whole lifetime.
package final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t

    package init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    package func lock() {
        os_unfair_lock_lock(pointer)
    }

    package func unlock() {
        os_unfair_lock_unlock(pointer)
    }

    package func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(pointer)
        defer { os_unfair_lock_unlock(pointer) }
        return try body()
    }
}
