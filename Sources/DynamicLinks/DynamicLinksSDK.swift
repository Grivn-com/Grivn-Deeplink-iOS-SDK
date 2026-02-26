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

@preconcurrency import UIKit

@objc
public final class DynamicLinksSDK: NSObject, @unchecked Sendable {

    /// SDK 版本号
    @objc public static let sdkVersion: String = "1.0.9"
    
    // MARK: - 单例 & 线程安全

    // Thread safety: all access to static mutable state goes through `lock`
    nonisolated(unsafe) private static var lock = UnfairLock()
    nonisolated(unsafe) private static var _shared: DynamicLinksSDK?
    nonisolated(unsafe) private static var _isInitialized: Bool = false
    nonisolated(unsafe) private static var _trustAllCerts: Bool = false
    nonisolated(unsafe) private static var _analyticsEnabled: Bool = true

    @objc public static var shared: DynamicLinksSDK {
        return lock.withLock {
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
    private var eventTracker: EventTracker?

    private override init() { super.init() }

    // MARK: - 初始化

    /// 启用或关闭调试模式
    ///
    /// 开启后，SDK 会以 `[GrivnSDK]` 标签输出 DEBUG 级别的日志（初始化、网络请求、
    /// Deferred Deeplink 检查等）。关闭后完全静默（NONE）。
    ///
    /// - Parameter enabled: true 为开启（DEBUG 级别），false 为关闭（NONE）
    @discardableResult
    @objc public static func setDebugMode(_ enabled: Bool) -> DynamicLinksSDK.Type {
        SDKLogger.shared.logLevel = enabled ? .debug : .none
        return self
    }

    /// 设置日志级别
    ///
    /// 可选级别：debug、info、warn、error、none（默认 none，完全静默）。
    ///
    /// - Parameter level: 日志级别
    @discardableResult
    public static func setLogLevel(_ level: LogLevel) -> DynamicLinksSDK.Type {
        SDKLogger.shared.logLevel = level
        return self
    }

    /// 注册自定义日志处理器
    ///
    /// 开发者可实现 `DynamicLinksLogHandler` 协议，将 SDK 日志接入
    /// CocoaLumberjack、Firebase Crashlytics 等外部日志系统。
    ///
    /// - Parameter handler: 自定义日志处理器
    @discardableResult
    public static func setLogger(_ handler: DynamicLinksLogHandler) -> DynamicLinksSDK.Type {
        SDKLogger.shared.handler = handler
        return self
    }

    /// 设置是否信任所有证书（仅开发环境使用）
    /// 必须在 initialize() 之前调用
    @discardableResult
    @objc public static func setTrustAllCerts(_ enabled: Bool) -> DynamicLinksSDK.Type {
        lock.withLock {
            _trustAllCerts = enabled
        }
        return self
    }

    /// Whether analytics data collection is enabled (deferred deeplink & install confirmation).
    /// When disabled, regular deep link handling (Universal Links) continues to work normally.
    @objc public static var analyticsEnabled: Bool {
        get { lock.withLock { _analyticsEnabled } }
        set { lock.withLock { _analyticsEnabled = newValue } }
    }

    /// Enable or disable analytics data collection (Swift-only fluent API).
    /// When disabled, `checkDeferredDeeplink` returns not-found and `confirmInstall` is a no-op.
    /// Regular deep link handling (Universal Links) is not affected.
    /// Objective-C: use the `analyticsEnabled` property setter instead.
    @discardableResult
    public static func setAnalyticsEnabled(_ enabled: Bool) -> DynamicLinksSDK.Type {
        lock.withLock { _analyticsEnabled = enabled }
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
        // Collect MainActor-isolated values before entering lock.
        // initialize() is always called from main thread (AppDelegate).
        dispatchPrecondition(condition: .onQueue(.main))
        var deviceId = ""
        var osVersion = ""
        var appVersion = ""
        MainActor.assumeIsolated {
            deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            osVersion = UIDevice.current.systemVersion
            appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        }

        return lock.withLock {
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

            // Initialize event tracker if analytics is enabled and projectId is available
            if _analyticsEnabled, let pid = projectId, let api = instance.apiService {
                instance.eventTracker = EventTracker(
                    apiService: api,
                    projectId: pid,
                    deviceId: deviceId,
                    deviceType: "ios",
                    osVersion: osVersion,
                    appVersion: appVersion,
                    sdkVersion: sdkVersion
                )
                Task { await instance.eventTracker?.start() }
            }

            SDKLogger.info("SDK initialized — baseUrl=\(instance.baseUrl), projectId=\(projectId ?? "(none)"), analyticsEnabled=\(_analyticsEnabled)")

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
                    SDKLogger.warn("Auto deferred-deeplink check failed", error)
                }
            }

            return instance
        }
    }

    /// 检查是否已初始化
    @objc public static func isInitialized() -> Bool {
        return lock.withLock { _isInitialized }
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
        lock.withLock {
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

        SDKLogger.debug("handleDynamicLink — url=\(incomingURL)")

        guard isValidDynamicLink(url: incomingURL) else {
            SDKLogger.warn("Invalid dynamic link: \(incomingURL)")
            throw DynamicLinksSDKError.invalidDynamicLink
        }

        guard let apiService = apiService else {
            throw DynamicLinksSDKError.notInitialized
        }

        let response = try await apiService.exchangeShortLink(requestedLink: incomingURL)

        guard let longLink = response.longLink,
              let dynamicLink = DynamicLink(longLink: longLink) else {
            SDKLogger.error("Failed to parse long link from exchange response")
            throw DynamicLinksSDKError.parseError(message: "Failed to parse long link", cause: nil)
        }

        SDKLogger.info("exchangeShortLink succeeded — longLink=\(longLink)")

        // Auto-event: deeplink_first_open or deeplink_reopen
        if DynamicLinksSDK.analyticsEnabled {
            let key = "grivn_deeplink_opened_\(incomingURL.absoluteString)"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                trackEvent(name: "deeplink_first_open", params: ["url": incomingURL.absoluteString])
            } else {
                trackEvent(name: "deeplink_reopen", params: ["url": incomingURL.absoluteString])
            }
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
        guard url.host != nil else {
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

        SDKLogger.info("Checking deferred deeplink (forceCheck=\(forceCheck))")

        // 标记已检查
        DeviceFingerprint.markFirstLaunchChecked()

        do {
            // 服务端会根据请求的 IP + UserAgent 生成指纹进行匹配
            let userAgent = await DeviceFingerprint.getUserAgent()
            let screenResolution = await DeviceFingerprint.getScreenResolution()
            let timezone = DeviceFingerprint.getTimezone()
            let language = DeviceFingerprint.getLanguage()

            SDKLogger.debug("Fingerprint matching — screen=\(screenResolution), tz=\(timezone), lang=\(language)")

            let response = try await apiService.getDeferredDeeplink(
                userAgent: userAgent,
                screenResolution: screenResolution,
                timezone: timezone,
                language: language
            )

            if response.found {
                SDKLogger.info("Deferred deeplink found via fingerprint")
                trackEvent(name: "deferred_deeplink_match", params: ["match_tier": "fingerprint"])
                // 确认安装
                try? await confirmInstallInternal()
            } else {
                SDKLogger.info("No deferred deeplink found")
            }

            // 转换 link_data
            var linkData: [String: Any]? = nil
            if let data = response.link_data {
                linkData = data.mapValues { $0.value }
            }

            return DeferredDeeplinkData(found: response.found, linkData: linkData)
        } catch {
            SDKLogger.error("checkDeferredDeeplink exception", error)
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

        // UIDevice properties are @MainActor in Swift 6
        let userAgent = await DeviceFingerprint.getUserAgent()
        let deviceModel = await MainActor.run { UIDevice.current.model }
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let appVersion = await MainActor.run { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

        SDKLogger.debug("confirmInstall — device=\(deviceModel), os=\(osVersion), appVersion=\(appVersion ?? "N/A")")

        _ = try await apiService.confirmInstall(
            userAgent: userAgent,
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion
        )
        trackEvent(name: "app_install")
        SDKLogger.info("Install confirmed")
    }

    /// 重置首次启动状态（用于测试）
    @objc
    public func resetDeferredDeeplinkState() {
        DeviceFingerprint.resetFirstLaunch()
    }
}

// MARK: - Event Tracking

extension DynamicLinksSDK {

    /// Sendable wrapper for `[String: Any]?` params that only contain JSON-primitive values.
    private struct SendableParams: @unchecked Sendable {
        let value: [String: Any]?
    }

    /// Track a custom event.
    ///
    /// Events are batched locally and flushed to the server every 30 seconds
    /// or when 20 events accumulate.
    ///
    /// - Parameters:
    ///   - name: Event name (e.g. "purchase", "sign_up")
    ///   - params: Optional event parameters
    public func trackEvent(name: String, params: [String: Any]? = nil) {
        guard DynamicLinksSDK.analyticsEnabled else { return }
        guard let tracker = eventTracker else {
            SDKLogger.warn("EventTracker not initialized — call initialize() with projectId first")
            return
        }
        let wrapped = SendableParams(value: params)
        Task { await tracker.trackEvent(name: name, params: wrapped.value) }
    }

    /// Set the user ID for event attribution.
    ///
    /// - Parameter userId: User identifier (e.g. your app's user ID)
    @objc public func setUserId(_ userId: String) {
        guard let tracker = eventTracker else {
            SDKLogger.warn("EventTracker not initialized — call initialize() with projectId first")
            return
        }
        Task { await tracker.setUserId(userId) }
    }

    /// Flush pending events to the server immediately.
    @objc public func flushEvents() {
        Task {
            await eventTracker?.flush()
        }
    }
}
