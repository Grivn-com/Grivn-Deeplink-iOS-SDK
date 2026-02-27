//
//  DynamicLinksSDK.swift
//  DynamicLinks
//
//  Main entry point for the DynamicLinks SDK.
//
//  Usage example:
//  ```swift
//  // Initialize (only handling links)
//  DynamicLinksSDK.initialize(
//      baseUrl: "https://api.grivn.com",
//      secretKey: "your_secret_key"
//  )
//
//  // Initialize (also creating links, requires projectId)
//  DynamicLinksSDK.initialize(
//      baseUrl: "https://api.grivn.com",
//      secretKey: "your_secret_key",
//      projectId: "your_project_id"
//  )
//
//  // Optional configuration
//  DynamicLinksSDK.configure(allowedHosts: ["acme.wayp.link"])
//
//  // Handle a dynamic link
//  let dynamicLink = try await DynamicLinksSDK.shared.handleDynamicLink(incomingURL)
//
//  // Shorten a link (requires projectId)
//  let response = try await DynamicLinksSDK.shared.shorten(dynamicLink: components)
//  ```

@preconcurrency import UIKit

@objc
public final class DynamicLinksSDK: NSObject, @unchecked Sendable {

    /// SDK version.
    @objc public static let sdkVersion: String = "1.0.9"
    
    // MARK: - Singleton & thread safety

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

    // MARK: - Configuration

    private var allowedHosts: [String] = []
    private var baseUrl: String = ""
    private var secretKey: String = ""
    private var projectId: String?
    private var apiService: ApiService?
    private var eventTracker: EventTracker?

    private override init() { super.init() }

    // MARK: - Initialization

    /// Enables or disables debug mode.
    ///
    /// When enabled, the SDK outputs DEBUG-level logs with the `[GrivnSDK]`
    /// tag (initialization, network requests, deferred deeplink checks, etc.).
    /// When disabled, logging is completely silent (`none`).
    ///
    /// - Parameter enabled: `true` for DEBUG level, `false` for `none`.
    @discardableResult
    @objc public static func setDebugMode(_ enabled: Bool) -> DynamicLinksSDK.Type {
        SDKLogger.shared.logLevel = enabled ? .debug : .none
        return self
    }

    /// Sets the log level.
    ///
    /// Available levels: `debug`, `info`, `warn`, `error`, `none`
    /// (default is `.none`, completely silent).
    ///
    /// - Parameter level: Log level.
    @discardableResult
    public static func setLogLevel(_ level: LogLevel) -> DynamicLinksSDK.Type {
        SDKLogger.shared.logLevel = level
        return self
    }

    /// Registers a custom log handler.
    ///
    /// Implement the `DynamicLinksLogHandler` protocol to forward SDK logs
    /// into CocoaLumberjack, Firebase Crashlytics, or other logging systems.
    ///
    /// - Parameter handler: Custom log handler.
    @discardableResult
    public static func setLogger(_ handler: DynamicLinksLogHandler) -> DynamicLinksSDK.Type {
        SDKLogger.shared.handler = handler
        return self
    }

    /// Controls whether to trust all SSL certificates (development only).
    /// Must be called before `initialize()`.
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

    /// Deferred deeplink callback type.
    public typealias DeferredDeeplinkCallback = @Sendable (DeferredDeeplinkData) -> Void

    /// Deferred deeplink callback instance.
    nonisolated(unsafe) private static var _deferredCallback: DeferredDeeplinkCallback?

    /// Initializes the SDK (simple version, without automatic deferred deeplink check).
    ///
    /// - Parameters:
    ///   - baseUrl: Backend API base URL (e.g. `"https://api.grivn.com"`).
    ///   - secretKey: Secret key (sent via the `X-API-Key` header).
    ///   - projectId: Optional project ID (used when creating links).
    @discardableResult
    @objc public static func initialize(
        baseUrl: String,
        secretKey: String,
        projectId: String? = nil
    ) -> DynamicLinksSDK {
        return initializeInternal(baseUrl: baseUrl, secretKey: secretKey, projectId: projectId, onDeferredDeeplink: nil)
    }

    /// Initializes the SDK and automatically checks for deferred deeplinks.
    ///
    /// On first launch, the SDK will automatically check whether there is a
    /// deferred deeplink and return the result via the callback. You do not
    /// need to call `checkDeferredDeeplink()` manually.
    ///
    /// Usage example:
    /// ```swift
    /// // Call from AppDelegate.didFinishLaunchingWithOptions
    /// DynamicLinksSDK.initialize(
    ///     baseUrl: "https://api.grivn.com",
    ///     secretKey: "your_secret_key",
    ///     projectId: "your_project_id"
    /// ) { result in
    ///     if result.found {
    ///         // Handle deferred deeplink
    ///         print("Found deferred deeplink: \(result.originalUrl ?? "")")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - baseUrl: Backend API base URL.
    ///   - secretKey: Secret key.
    ///   - projectId: Optional project ID.
    ///   - onDeferredDeeplink: Optional deferred deeplink callback; if nil,
    ///     the SDK will silently report the install.
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

            // Automatically check deferred deeplink
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

    /// Returns whether the SDK has been initialized.
    @objc public static func isInitialized() -> Bool {
        return lock.withLock { _isInitialized }
    }

    /// Sets the project ID (can be called after `initialize()`).
    ///
    /// - Parameter projectId: Project ID used when creating links.
    @discardableResult
    @objc public func setProjectId(_ projectId: String) -> DynamicLinksSDK {
        self.projectId = projectId
        return self
    }

    /// Configures the list of allowed domains.
    /// - Parameter allowedHosts: Allowed hostnames (e.g. `["acme.wayp.link", "preview.acme.wayp.link"]`).
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

// MARK: - Dynamic link handling

extension DynamicLinksSDK {

    /// Handles an incoming dynamic link URL.
    ///
    /// - Parameter incomingURL: The received dynamic link URL.
    /// - Returns: A parsed `DynamicLink` object.
    /// - Throws: `DynamicLinksSDKError` on failure.
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

    /// Handles a dynamic link (Objective-C compatibility).
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

// MARK: - Pasteboard link detection

extension DynamicLinksSDK {

    /// Check if pasteboard may contain a dynamic link (does NOT trigger iOS 16+ paste prompt)
    ///
    /// Use this to decide whether to show a "Paste link" button/banner.
    /// Only when user taps the button should you call `handlePasteboardDynamicLink()`.
    @objc public func hasPossibleDynamicLink() -> Bool {
        return UIPasteboard.general.hasURLs
    }

    /// Checks and handles a dynamic link from the pasteboard.
    /// The pasteboard is only checked once per app launch.
    ///
    /// - Returns: A parsed `DynamicLink` object.
    /// - Throws: `DynamicLinksSDKError`.
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
                // Clear the link from the pasteboard
                if pasteboard.string == copiedURLString {
                    pasteboard.string = nil
                }
                return dynamicLink
            }
        }
        throw DynamicLinksSDKError.noURLInPasteboard
    }

    /// Checks and handles a dynamic link from the pasteboard (Objective-C compatibility).
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

    /// Resets the pasteboard-check state (for testing).
    @objc public func resetPasteboardCheck() {
        UserDefaults.standard.removeObject(forKey: "hasCheckedPasteboardForDynamicLink")
    }
}

// MARK: - Shortening links

extension DynamicLinksSDK {

    /// Shortens a dynamic link.
    ///
    /// - Parameters:
    ///   - dynamicLink: `DynamicLinkComponents` describing the link.
    ///   - projectId: Optional project ID. If not set via `initialize()` or
    ///     `setProjectId()`, it must be provided here.
    /// - Returns: `DynamicLinkShortenResponse`.
    /// - Throws: `DynamicLinksSDKError`.
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

    /// Shortens a dynamic link (Objective-C compatibility).
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

// MARK: - Link validation

extension DynamicLinksSDK {

    /// Checks whether the given URL is a valid dynamic link.
    ///
    /// - Parameter url: URL to check.
    /// - Returns: `true` if the URL is a valid dynamic link.
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

    /// Checks for and retrieves a deferred deeplink (post-install deeplink).
    ///
    /// When a user is redirected to the App Store via a deeplink and installs
    /// the app, call this method on first launch to obtain the original link
    /// data. This method only returns data on the first launch; subsequent
    /// calls will return `found = false`.
    ///
    /// Note: The server generates a fingerprint using the request IP address
    /// and User-Agent, so the user must be on the same network (same IP) to
    /// be matched successfully.
    ///
    /// Usage example:
    /// ```swift
    /// // Call from AppDelegate or SceneDelegate
    /// Task {
    ///     let result = try await DynamicLinksSDK.shared.checkDeferredDeeplink()
    ///     if result.found {
    ///         // Handle deferred deeplink
    ///         let deeplinkId = result.deeplinkId
    ///         let utmSource = result.utmSource
    ///         // Navigate to the target screen...
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter forceCheck: Whether to force a check (ignores the first-launch flag, useful for testing).
    /// - Returns: `DeferredDeeplinkData` containing whether a deferred deeplink was found and its data.
    /// - Throws: `DynamicLinksSDKError.notInitialized` if the SDK has not been initialized.
    public func checkDeferredDeeplink(forceCheck: Bool = false) async throws -> DeferredDeeplinkData {
        try ensureInitialized()

        // Analytics opt-out: skip deferred deeplink check
        if !DynamicLinksSDK.analyticsEnabled {
            return DeferredDeeplinkData(found: false, linkData: nil)
        }

        guard let apiService = apiService else {
            throw DynamicLinksSDKError.notInitialized
        }

        // Check whether this is the first launch
        if !forceCheck && !DeviceFingerprint.isFirstLaunch() {
            return DeferredDeeplinkData(found: false, linkData: nil)
        }

        SDKLogger.info("Checking deferred deeplink (forceCheck=\(forceCheck))")

        // Mark that the first-launch check has been performed
        DeviceFingerprint.markFirstLaunchChecked()

        do {
            // The server performs fingerprint matching based on IP + User-Agent.
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
                try? await confirmInstallInternal()
            } else {
                SDKLogger.info("No deferred deeplink found")
            }

            // Convert `link_data` to `[String: Any]`
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

    /// Checks for and retrieves a deferred deeplink (Objective-C compatibility).
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

    /// Manually confirms an install (normally called by `checkDeferredDeeplink`).
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

    /// Resets the first-launch state (for testing).
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
