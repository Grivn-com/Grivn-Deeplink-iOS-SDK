//
//  DynamicLinksSDKError.swift
//  DynamicLinks
//

import Foundation

/// DynamicLinks SDK 错误类型
/// 匹配 Android SDK 的错误定义
public enum DynamicLinksSDKError: Error, LocalizedError {
    
    /// SDK 未初始化
    case notInitialized
    
    /// 无效的动态链接
    case invalidDynamicLink
    
    /// 项目 ID 未设置（创建链接时需要）
    case projectIdNotSet
    
    /// 粘贴板中没有 URL
    case noURLInPasteboard
    
    /// 已经检查过粘贴板
    case alreadyCheckedPasteboard
    
    /// 网络错误
    case networkError(message: String, cause: Error?)
    
    /// 服务器返回错误
    case serverError(message: String, code: Int)
    
    /// 解析响应失败
    case parseError(message: String, cause: Error?)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK not initialized. Call DynamicLinksSDK.init() first."
        case .invalidDynamicLink:
            return "Link is invalid"
        case .projectIdNotSet:
            return "Project ID not set. Call init() with projectId or setProjectId() or pass projectId to shorten()."
        case .noURLInPasteboard:
            return "No valid URL found in pasteboard"
        case .alreadyCheckedPasteboard:
            return "Already checked pasteboard for Dynamic Link once, further checks will fail immediately as handling now goes through handleDynamicLink"
        case .networkError(let message, _):
            return "Network error: \(message)"
        case .serverError(let message, let code):
            return "Server error (\(code)): \(message)"
        case .parseError(let message, _):
            return "Parse error: \(message)"
        }
    }
    
    /// 转换为 NSError 以支持 Objective-C
    public var nsError: NSError {
        let domain = "com.DynamicLinks"
        let code: Int
        let userInfo: [String: Any]
        
        switch self {
        case .notInitialized:
            code = 1
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .invalidDynamicLink:
            code = 2
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .projectIdNotSet:
            code = 3
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .noURLInPasteboard:
            code = 4
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .alreadyCheckedPasteboard:
            code = 5
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .networkError(_, let cause):
            code = 6
            userInfo = [
                NSLocalizedDescriptionKey: errorDescription ?? "",
                NSUnderlyingErrorKey: cause as Any
            ]
        case .serverError(_, let serverCode):
            code = serverCode
            userInfo = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        case .parseError(_, let cause):
            code = 7
            userInfo = [
                NSLocalizedDescriptionKey: errorDescription ?? "",
                NSUnderlyingErrorKey: cause as Any
            ]
        }
        
        return NSError(domain: domain, code: code, userInfo: userInfo)
    }
}
