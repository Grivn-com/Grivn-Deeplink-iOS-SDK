//
//  DynamicLinksLogger.swift
//  DynamicLinks
//
//  SDK 日志框架
//

import Foundation
import os.log

/// SDK 日志级别
@objc public enum LogLevel: Int, Sendable {
    /// 详细调试信息（API 请求/响应、指纹详情等）
    case debug = 0
    /// 关键流程信息（初始化、匹配结果等）
    case info = 1
    /// 可恢复的异常（网络超时重试、非关键失败等）
    case warn = 2
    /// 不可恢复的错误
    case error = 3
    /// 完全静默
    case none = 4
}

/// SDK 日志接口
///
/// 开发者可实现此协议，将 SDK 日志接入 CocoaLumberjack、Firebase Crashlytics 等外部日志系统。
///
/// 使用示例:
/// ```swift
/// class MyLogHandler: DynamicLinksLogHandler {
///     func log(level: LogLevel, tag: String, message: String, error: Error?) {
///         // Forward to your logging system
///     }
/// }
/// DynamicLinksSDK.setLogger(MyLogHandler())
/// ```
public protocol DynamicLinksLogHandler: Sendable {
    /// 输出日志
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - tag: 日志标签（固定为 "GrivnSDK"）
    ///   - message: 日志内容
    ///   - error: 关联的错误（可选）
    func log(level: LogLevel, tag: String, message: String, error: Error?)
}

/// 默认日志实现，使用 os_log
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

/// SDK 内部日志工具
///
/// 生产模式（默认）完全静默。调用 `DynamicLinksSDK.setDebugMode(true)` 后
/// 以 `[GrivnSDK]` 标签输出调试信息。
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

    /// 对 API Key 脱敏：保留前 4 位和后 3 位，中间用 *** 替代
    static func maskApiKey(_ key: String) -> String {
        if key.count <= 10 { return "***" }
        return "\(key.prefix(4))***\(key.suffix(3))"
    }
}
