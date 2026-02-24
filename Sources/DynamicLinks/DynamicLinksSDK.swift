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
    @objc public static let sdkVersion: String = "1.0.3"
    
    // MARK: - 单例 & 线程安全
    
    nonisolated(unsafe) private static var lock = DispatchQueue(label: "com.DynamicLinks.lock")
    nonisolated(unsafe) private static var _shared: DynamicLinksSDK?
    nonisolated(unsafe) private static var _isInitialized: Bool = false
    nonisolated(unsafe) private static var _trustAllCerts: Bool = false
    nonisolated(unsafe) private static var _analyticsEnabled: Bool = true
    
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
    
    /// Whether analytics data collection is enabled (deferred deeplink & install confirmation).
    /// When disabled, regular deep link handling (Universal Links) continues to work normally.
    @objc public static var analyticsEnabled: Bool {
        get { lock.sync { _analyticsEnabled } }
        set { lock.sync { _analyticsEnabled = newValue } }
    }

    /// Enable or disable analytics data collection.
    /// When disabled, `checkDeferredDeeplink` returns not-found and `confirmInstall` is a no-op.
    /// Regular deep link handling (Universal Links) is not affected.
    @discardableResult
    @objc public static func setAnalyticsEnabled(_ enabled: Bool) -> DynamicLinksSDK.Type {
        lock.sync { _analyticsEnabled = enabled }
        return self
    }

    /// Deferred Deeplink 回调类型
    public typealias DeferredDeeplinkCallback = @Sendable (DeferredDeeplinkData) -> Void
    
    /// Deferred Deeplink 回调
    nonisolated(unsafe) private static var _deferredCallback: DeferredDeeplinkCallback?
    
    /// 初始化 SDK（简单版本，不自动检查 Deferred Deeplink）
    ///
    /// - Parameters:
    ///   - baseUrl: 后端 API Base URL (例如 "https://api.grivn.com")
    ///   - secretKey: Secret Key（通过 X-API-Key header 发送）
    ///   - projectId: 项目 ID（可选，用于创建链接时指定所属项目）
    @discardableResult
    @objc public static func initialize(
        baseUrl: String,
        secretKey: String,
        projectId: String? = nil
    ) -> DynamicLinksSDK {
        return initializeInternal(baseUrl: baseUrl, secretKey: secretKey, projectId: projectId, onDeferredDeeplink: nil)
    }
    
    /// 初始化 SDK 并自动检查 Deferred Deeplink
    ///
    /// SDK 会在首次启动时自动检查是否有延迟深链，并通过回调返回结果。
    /// 开发者无需额外调用 checkDeferredDeeplink()。
    ///
    /// 使用示例:
    /// ```swift
    /// // 在 AppDelegate.didFinishLaunchingWithOptions 中调用
    /// DynamicLinksSDK.initialize(
    ///     baseUrl: "https://api.grivn.com",
    ///     secretKey: "your_secret_key",
    ///     projectId: "your_project_id"
    /// ) { result in
    ///     if result.found {
    ///         // 处理延迟深链
    ///         print("Found deferred deeplink: \(result.originalUrl ?? "")")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - baseUrl: 后端 API Base URL
    ///   - secretKey: Secret Key
    ///   - projectId: 项目 ID（可选）
    ///   - onDeferredDeeplink: 延迟深链回调（可选，不传则静默上报安装）
    @discardableResult
    public static func initialize(
        baseUrl: String,
        secretKey: String,
        projectId: String? = nil,
        onDeferredDeeplink: DeferredDeeplinkCallback? = nil
    ) -> DynamicLinksSDK {
        return initializeInternal(baseUrl: baseUrl, secretKey: secretKey, projectId: projectId, onDeferredDeeplink: onDeferredDeeplink)
    }
    
    private static func initializeInternal(
        baseUrl: String,
        secretKey: String,
        projectId: String?,
        onDeferredDeeplink: DeferredDeeplinkCallback?
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
            _deferredCallback = onDeferredDeeplink
            
            // 自动检查 Deferred Deeplink
            Task {
                do {
                    let result = try await instance.checkDeferredDeeplink(forceCheck: false)
                    if let callback = _deferredCallback {
                        await MainActor.run {
                            callback(result)
                        }
                    }
                } catch {
                    // 静默失败，不影响 App 启动
                }
            }
            
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

    /// Check if pasteboard may contain a dynamic link (does NOT trigger iOS 16+ paste prompt)
    ///
    /// Use this to decide whether to show a "Paste link" button/banner.
    /// Only when user taps the button should you call `handlePasteboardDynamicLink()`.
    @objc public func hasPossibleDynamicLink() -> Bool {
        return UIPasteboard.general.hasURLs
    }

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

// MARK: - Deferred Deeplink

extension DynamicLinksSDK {
    
    /// 检查并获取延迟深链（首次安装后的 Deeplink）
    ///
    /// 当用户通过 Deeplink 跳转到 App Store 下载 App 后，首次打开时调用此方法获取原始链接数据。
    /// 此方法只会在首次启动时返回数据，后续调用将返回 found=false。
    ///
    /// 注意：服务端会根据请求的 IP 地址和 User-Agent 生成指纹进行匹配，
    /// 因此用户必须在相同的网络环境下（相同 IP）才能匹配成功。
    ///
    /// 使用示例:
    /// ```swift
    /// // 在 AppDelegate 或 SceneDelegate 中调用
    /// Task {
    ///     let result = try await DynamicLinksSDK.shared.checkDeferredDeeplink()
    ///     if result.found {
    ///         // 处理延迟深链
    ///         let deeplinkId = result.deeplinkId
    ///         let utmSource = result.utmSource
    ///         // 导航到目标页面...
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter forceCheck: 是否强制检查（忽略首次启动标记，用于测试）
    /// - Returns: DeferredDeeplinkData 包含是否找到延迟深链及链接数据
    /// - Throws: DynamicLinksSDKError.notInitialized 如果 SDK 未初始化
    public func checkDeferredDeeplink(forceCheck: Bool = false) async throws -> DeferredDeeplinkData {
        try ensureInitialized()

        // Analytics opt-out: skip deferred deeplink check
        if !DynamicLinksSDK.analyticsEnabled {
            return DeferredDeeplinkData(found: false, linkData: nil)
        }

        guard let apiService = apiService else {
            throw DynamicLinksSDKError.notInitialized
        }

        // 检查是否是首次启动
        if !forceCheck && !DeviceFingerprint.isFirstLaunch() {
            return DeferredDeeplinkData(found: false, linkData: nil)
        }
        
        // 标记已检查
        DeviceFingerprint.markFirstLaunchChecked()
        
        do {
            // 服务端会根据请求的 IP + UserAgent 生成指纹进行匹配
            let userAgent = DeviceFingerprint.getUserAgent()
            let screenResolution = DeviceFingerprint.getScreenResolution()
            let timezone = DeviceFingerprint.getTimezone()
            let language = DeviceFingerprint.getLanguage()
            
            let response = try await apiService.getDeferredDeeplink(
                userAgent: userAgent,
                screenResolution: screenResolution,
                timezone: timezone,
                language: language
            )
            
            if response.found {
                // 确认安装
                try? await confirmInstallInternal()
            }
            
            // 转换 link_data
            var linkData: [String: Any]? = nil
            if let data = response.link_data {
                linkData = data.mapValues { $0.value }
            }
            
            return DeferredDeeplinkData(found: response.found, linkData: linkData)
        } catch {
            return DeferredDeeplinkData(found: false, linkData: nil)
        }
    }
    
    /// 检查并获取延迟深链 (Objective-C 兼容)
    @objc
    public func checkDeferredDeeplink(
        forceCheck: Bool = false,
        completion: @Sendable @escaping (DeferredDeeplinkData?, NSError?) -> Void
    ) {
        Task {
            do {
                let result = try await checkDeferredDeeplink(forceCheck: forceCheck)
                await MainActor.run {
                    completion(result, nil)
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
    
    /// 手动确认安装（通常由 checkDeferredDeeplink 自动调用）
    public func confirmInstall() async throws {
        try ensureInitialized()
        try await confirmInstallInternal()
    }
    
    private func confirmInstallInternal() async throws {
        // Analytics opt-out: skip install confirmation
        if !DynamicLinksSDK.analyticsEnabled { return }

        guard let apiService = apiService else { return }
        
        // 服务端会根据请求的 IP + UserAgent 生成指纹（UIDevice 在 Swift 6 中为 MainActor 隔离，需 await）
        let userAgent = DeviceFingerprint.getUserAgent()
        let deviceModel = await MainActor.run { UIDevice.current.model }
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let appVersion = await MainActor.run { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
        
        _ = try await apiService.confirmInstall(
            userAgent: userAgent,
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion
        )
    }
    
    /// 重置首次启动状态（用于测试）
    @objc
    public func resetDeferredDeeplinkState() {
        DeviceFingerprint.resetFirstLaunch()
    }
}
