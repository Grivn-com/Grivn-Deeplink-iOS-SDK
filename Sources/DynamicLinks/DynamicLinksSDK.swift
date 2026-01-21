//
//  DynamicLinksSDK.swift
//  DynamicLinks
//
//  DynamicLinks SDK 主入口
//
//  使用示例:
//  ```swift
//  // 初始化（仅处理链接时）
//  DynamicLinksSDK.initialize(
//      baseUrl: "https://api.grivn.com",
//      secretKey: "your_secret_key"
//  )
//
//  // 初始化（需要创建链接时，需要提供 projectId）
//  DynamicLinksSDK.initialize(
//      baseUrl: "https://api.grivn.com",
//      secretKey: "your_secret_key",
//      projectId: "your_project_id"
//  )
//
//  // 可选配置
//  DynamicLinksSDK.configure(allowedHosts: ["acme.wayp.link"])
//
//  // 处理动态链接
//  let dynamicLink = try await DynamicLinksSDK.shared.handleDynamicLink(incomingURL)
//
//  // 缩短链接（需要 projectId）
//  let response = try await DynamicLinksSDK.shared.shorten(dynamicLink: components)
//  ```

import UIKit

@objc
public final class DynamicLinksSDK: NSObject, @unchecked Sendable {
    
    /// SDK 版本号
    @objc public static let sdkVersion: String = "1.0.0"
    
    // MARK: - 单例 & 线程安全
    
    nonisolated(unsafe) private static var lock = DispatchQueue(label: "com.DynamicLinks.lock")
    nonisolated(unsafe) private static var _shared: DynamicLinksSDK?
    nonisolated(unsafe) private static var _isInitialized: Bool = false
    nonisolated(unsafe) private static var _trustAllCerts: Bool = false
    
    @objc public static var shared: DynamicLinksSDK {
        return lock.sync {
            guard let instance = _shared else {
                assertionFailure("Must call DynamicLinksSDK.initialize() first")
                return DynamicLinksSDK()
            }
            return instance
        }
    }
    
    // MARK: - 配置
    
    private var allowedHosts: [String] = []
    private var baseUrl: String = ""
    private var secretKey: String = ""
    private var projectId: String?
    private var apiService: ApiService?
    
    private override init() { super.init() }
    
    // MARK: - 初始化
    
    /// 设置是否信任所有证书（仅开发环境使用）
    /// 必须在 initialize() 之前调用
    @discardableResult
    @objc public static func setTrustAllCerts(_ enabled: Bool) -> DynamicLinksSDK.Type {
        lock.sync {
            _trustAllCerts = enabled
        }
        return self
    }
    
    /// 初始化 SDK
    ///
    /// - Parameters:
    ///   - baseUrl: 后端 API Base URL (例如 "https://api.grivn.com")
    ///   - secretKey: Secret Key（通过 X-API-Key header 发送）
    ///   - projectId: 项目 ID（可选，用于创建链接时指定所属项目。如果只处理链接可以不传）
    @discardableResult
    @objc public static func initialize(
        baseUrl: String,
        secretKey: String,
        projectId: String? = nil
    ) -> DynamicLinksSDK {
        return lock.sync {
            precondition(!baseUrl.isEmpty, "baseUrl cannot be empty")
            precondition(!secretKey.isEmpty, "secretKey cannot be empty")
            
            let instance = DynamicLinksSDK()
            instance.baseUrl = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
            instance.secretKey = secretKey
            instance.projectId = projectId
            
            instance.apiService = ApiService(
                baseUrl: instance.baseUrl,
                secretKey: instance.secretKey,
                timeout: 30,
                trustAllCerts: _trustAllCerts
            )
            
            _shared = instance
            _isInitialized = true
            return instance
        }
    }
    
    /// 检查是否已初始化
    @objc public static func isInitialized() -> Bool {
        return lock.sync { _isInitialized }
    }
    
    /// 设置项目 ID（可在 initialize() 后单独设置）
    ///
    /// - Parameter projectId: 项目 ID（用于创建链接）
    @discardableResult
    @objc public func setProjectId(_ projectId: String) -> DynamicLinksSDK {
        self.projectId = projectId
        return self
    }
    
    /// 配置允许的域名列表
    /// - Parameter allowedHosts: 允许的域名列表 (例如 ["acme.wayp.link", "preview.acme.wayp.link"])
    @objc public static func configure(allowedHosts: [String]) {
        lock.sync {
            _shared?.allowedHosts = allowedHosts
        }
    }
    
    private func ensureInitialized() throws {
        guard DynamicLinksSDK.isInitialized() else {
            throw DynamicLinksSDKError.notInitialized
        }
    }
}

// MARK: - 处理动态链接

extension DynamicLinksSDK {
    
    /// 处理动态链接
    ///
    /// - Parameter incomingURL: 收到的动态链接 URL
    /// - Returns: 解析后的 DynamicLink 对象
    /// - Throws: DynamicLinksSDKError
    public func handleDynamicLink(_ incomingURL: URL) async throws -> DynamicLink {
        try ensureInitialized()
        
        guard isValidDynamicLink(url: incomingURL) else {
            throw DynamicLinksSDKError.invalidDynamicLink
        }
        
        guard let apiService = apiService else {
            throw DynamicLinksSDKError.notInitialized
        }
        
        let response = try await apiService.exchangeShortLink(requestedLink: incomingURL)
        
        guard let longLink = response.longLink,
              let dynamicLink = DynamicLink(longLink: longLink) else {
            throw DynamicLinksSDKError.parseError(message: "Failed to parse long link", cause: nil)
        }
        
        return dynamicLink
    }
    
    /// 处理动态链接 (Objective-C 兼容)
    @objc
    public func handleDynamicLink(_ incomingURL: URL, completion: @Sendable @escaping (DynamicLink?, NSError?) -> Void) {
        Task {
            do {
                let dynamicLink = try await handleDynamicLink(incomingURL)
                await MainActor.run {
                    completion(dynamicLink, nil)
                }
            } catch let error as DynamicLinksSDKError {
                await MainActor.run {
                    completion(nil, error.nsError)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error as NSError)
                }
            }
        }
    }
}

// MARK: - 粘贴板链接检测

extension DynamicLinksSDK {
    
    /// 检查并处理粘贴板中的动态链接
    /// 每次 App 启动只会检查一次粘贴板
    ///
    /// - Returns: 解析后的 DynamicLink 对象
    /// - Throws: DynamicLinksSDKError
    public func handlePasteboardDynamicLink() async throws -> DynamicLink {
        let hasCheckedPasteboardKey = "hasCheckedPasteboardForDynamicLink"
        
        if UserDefaults.standard.bool(forKey: hasCheckedPasteboardKey) {
            throw DynamicLinksSDKError.alreadyCheckedPasteboard
        }
        
        UserDefaults.standard.set(true, forKey: hasCheckedPasteboardKey)
        
        let pasteboard = UIPasteboard.general
        if pasteboard.hasURLs {
            if let copiedURLString = pasteboard.string,
               let url = URL(string: copiedURLString) {
                let dynamicLink = try await handleDynamicLink(url)
                // 清除粘贴板中的链接
                if pasteboard.string == copiedURLString {
                    pasteboard.string = nil
                }
                return dynamicLink
            }
        }
        throw DynamicLinksSDKError.noURLInPasteboard
    }
    
    /// 检查并处理粘贴板中的动态链接 (Objective-C 兼容)
    @objc
    public func handlePasteboardDynamicLink(completion: @Sendable @escaping (DynamicLink?, NSError?) -> Void) {
        Task {
            do {
                let dynamicLink = try await handlePasteboardDynamicLink()
                await MainActor.run {
                    completion(dynamicLink, nil)
                }
            } catch let error as DynamicLinksSDKError {
                await MainActor.run {
                    completion(nil, error.nsError)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error as NSError)
                }
            }
        }
    }
    
    /// 重置粘贴板检查状态（用于测试）
    @objc public func resetPasteboardCheck() {
        UserDefaults.standard.removeObject(forKey: "hasCheckedPasteboardForDynamicLink")
    }
}

// MARK: - 缩短链接

extension DynamicLinksSDK {
    
    /// 缩短动态链接
    ///
    /// - Parameters:
    ///   - dynamicLink: DynamicLinkComponents 对象
    ///   - projectId: 项目 ID（可选，如果未在 initialize() 或 setProjectId() 中设置，则必须在此传入）
    /// - Returns: DynamicLinkShortenResponse
    /// - Throws: DynamicLinksSDKError
    public func shorten(
        dynamicLink: DynamicLinkComponents,
        projectId: String? = nil
    ) async throws -> DynamicLinkShortenResponse {
        try ensureInitialized()
        
        guard let apiService = apiService else {
            throw DynamicLinksSDKError.notInitialized
        }
        
        let effectiveProjectId = projectId ?? self.projectId
        guard let finalProjectId = effectiveProjectId else {
            throw DynamicLinksSDKError.projectIdNotSet
        }
        
        return try await apiService.shortenUrl(projectId: finalProjectId, components: dynamicLink)
    }
    
    /// 缩短动态链接 (Objective-C 兼容)
    @objc
    public func shorten(
        dynamicLink: DynamicLinkComponents,
        completion: @Sendable @escaping (DynamicLinkShortenResponse?, NSError?) -> Void
    ) {
        Task {
            do {
                let response = try await shorten(dynamicLink: dynamicLink)
                await MainActor.run {
                    completion(response, nil)
                }
            } catch let error as DynamicLinksSDKError {
                await MainActor.run {
                    completion(nil, error.nsError)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error as NSError)
                }
            }
        }
    }
}

// MARK: - 验证链接

extension DynamicLinksSDK {
    
    /// 检查 URL 是否是有效的动态链接
    ///
    /// - Parameter url: 要检查的 URL
    /// - Returns: 如果是有效的动态链接返回 true
    @objc public func isValidDynamicLink(url: URL) -> Bool {
        guard let host = url.host else {
            return false
        }
        let canParse = isAllowedCustomDomain(url)
        let matchesShortLinkFormat = url.path.range(of: "/[^/]+", options: .regularExpression) != nil
        return canParse && matchesShortLinkFormat
    }
    
    private func isAllowedCustomDomain(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return allowedHosts.contains(host)
    }
}
