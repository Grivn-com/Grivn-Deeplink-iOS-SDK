//
//  DynamicLinksLogger.swift
//  DynamicLinks
//
//  SDK logging framework.
//

import Foundation
import os.log

/// SDK log levels.
@objc public enum LogLevel: Int, Sendable {
    /// Verbose debug information (API request/response, fingerprint details, etc.).
    case debug = 0
    /// Key flow information (initialization, matching results, etc.).
    case info = 1
    /// Recoverable issues (network timeouts with retries, non-critical failures, etc.).
    case warn = 2
    /// Non-recoverable errors.
    case error = 3
    /// Completely silent.
    case none = 4
}

/// SDK logging interface.
///
/// Implement this protocol to forward SDK logs into CocoaLumberjack,
/// Firebase Crashlytics, or other external logging systems.
///
/// Example:
/// ```swift
/// class MyLogHandler: DynamicLinksLogHandler {
///     func log(level: LogLevel, tag: String, message: String, error: Error?) {
///         // Forward to your logging system
///     }
/// }
/// DynamicLinksSDK.setLogger(MyLogHandler())
/// ```
public protocol DynamicLinksLogHandler: Sendable {
    /// Outputs a log entry.
    ///
    /// - Parameters:
    ///   - level: Log level.
    ///   - tag: Log tag (fixed to `"GrivnSDK"`).
    ///   - message: Log message.
    ///   - error: Optional associated error.
    func log(level: LogLevel, tag: String, message: String, error: Error?)
}

/// Default log implementation using `os_log`.
internal final class DefaultLogHandler: DynamicLinksLogHandler {
    private let osLog = OSLog(subsystem: "com.grivn.dynamiclinks", category: "GrivnSDK")

    func log(level: LogLevel, tag: String, message: String, error: Error?) {
        let errorSuffix = error.map { " | error: \($0.localizedDescription)" } ?? ""
        let fullMessage = "[\(tag)] \(message)\(errorSuffix)"

        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", fullMessage)
        case .info:
            os_log(.info, log: osLog, "%{public}@", fullMessage)
        case .warn:
            os_log(.fault, log: osLog, "%{public}@", fullMessage)
        case .error:
            os_log(.error, log: osLog, "%{public}@", fullMessage)
        case .none:
            break
        }
    }
}

/// Internal SDK logging utility.
///
/// In production mode (default) this is completely silent. After calling
/// `DynamicLinksSDK.setDebugMode(true)` it outputs debug information with
/// the `[GrivnSDK]` tag.
internal final class SDKLogger: Sendable {
    static let shared = SDKLogger()

    private static let TAG = "GrivnSDK"

    // Thread safety: all access goes through `lock` via computed properties
    private let lock = UnfairLock()
    nonisolated(unsafe) private var _logLevel: LogLevel = .none
    nonisolated(unsafe) private var _handler: DynamicLinksLogHandler = DefaultLogHandler()

    var logLevel: LogLevel {
        get { lock.withLock { _logLevel } }
        set { lock.withLock { _logLevel = newValue } }
    }

    var handler: DynamicLinksLogHandler {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    private init() {}

    static func debug(_ message: String) {
        guard shared.logLevel.rawValue <= LogLevel.debug.rawValue else { return }
        shared.handler.log(level: .debug, tag: TAG, message: message, error: nil)
    }

    static func info(_ message: String) {
        guard shared.logLevel.rawValue <= LogLevel.info.rawValue else { return }
        shared.handler.log(level: .info, tag: TAG, message: message, error: nil)
    }

    static func warn(_ message: String, _ error: Error? = nil) {
        guard shared.logLevel.rawValue <= LogLevel.warn.rawValue else { return }
        shared.handler.log(level: .warn, tag: TAG, message: message, error: error)
    }

    static func error(_ message: String, _ error: Error? = nil) {
        guard shared.logLevel.rawValue <= LogLevel.error.rawValue else { return }
        shared.handler.log(level: .error, tag: TAG, message: message, error: error)
    }

    /// Masks the API key: keeps first 4 and last 3 characters, middle replaced with ***.
    static func maskApiKey(_ key: String) -> String {
        if key.count <= 10 { return "***" }
        return "\(key.prefix(4))***\(key.suffix(3))"
    }
}
