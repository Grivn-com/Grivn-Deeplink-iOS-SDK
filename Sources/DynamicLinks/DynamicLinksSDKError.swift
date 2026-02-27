//
//  DynamicLinksSDKError.swift
//  DynamicLinks
//

import Foundation

/// DynamicLinks SDK error types.
/// Mirrors the error definitions used in the Android SDK.
public enum DynamicLinksSDKError: Error, LocalizedError {
    
    /// SDK has not been initialized.
    case notInitialized
    
    /// The dynamic link is invalid.
    case invalidDynamicLink
    
    /// Project ID has not been set (required when creating links).
    case projectIdNotSet
    
    /// No URL was found in the pasteboard.
    case noURLInPasteboard
    
    /// The pasteboard has already been checked.
    case alreadyCheckedPasteboard
    
    /// Network error.
    case networkError(message: String, cause: Error?)
    
    /// Server returned an error.
    case serverError(message: String, code: Int)
    
    /// Failed to parse the response.
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
    
    /// Converts to `NSError` for Objective-C compatibility.
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
