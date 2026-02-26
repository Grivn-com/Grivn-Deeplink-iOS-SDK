//
//  UnfairLock.swift
//  DynamicLinks
//
//  Lightweight lock wrapper around os_unfair_lock for thread-safe mutable state.
//

import os

internal struct UnfairLock: @unchecked Sendable {
    private let _lock: os_unfair_lock_t

    init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock())
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try body()
    }
}
