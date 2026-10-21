//
//  DeferredDeeplink.swift
//  DynamicLinks
//
//  Deferred deeplink data model and helper utilities.
//

import UIKit

/// Deferred deeplink data.
///
/// When a user is redirected to the App Store via a deeplink and installs
/// the app, the original link data can be retrieved on first launch.
/// @unchecked Sendable: all properties are `let` and contain only JSON-primitive values.
@objc public class DeferredDeeplinkData: NSObject, @unchecked Sendable {

    /// Whether a deferred deeplink was found.
    @objc public let found: Bool

    /// Original link data returned from the backend.
    @objc public let linkData: [String: Any]?

    /// Returns the original deeplink ID.
    @objc public var deeplinkId: String? {
        return linkData?["deeplink_id"] as? String
    }

    /// Returns the project ID.
    @objc public var projectId: String? {
        return linkData?["project_id"] as? String
    }

    /// Returns the original URL.
    @objc public var originalUrl: String? {
        return linkData?["original_url"] as? String
    }

    /// Returns the UTM source.
    @objc public var utmSource: String? {
        return linkData?["utm_source"] as? String
    }

    /// Returns the UTM medium.
    @objc public var utmMedium: String? {
        return linkData?["utm_medium"] as? String
    }

    /// Returns the UTM campaign.
    @objc public var utmCampaign: String? {
        return linkData?["utm_campaign"] as? String
    }

    /// Returns the referer.
    @objc public var referer: String? {
        return linkData?["referer"] as? String
    }

    /// Returns custom data by key.
    @objc public func getCustomData(key: String) -> Any? {
        return linkData?[key]
    }

    init(found: Bool, linkData: [String: Any]?) {
        self.found = found
        self.linkData = linkData
        super.init()
    }
}

/// First-launch bookkeeping and the request details for deferred deep link
/// lookup.
///
/// The SDK computes no device identifier of its own. It sends a User-Agent
/// and the language; the server matches them, with the request IP, against
/// recent clicks on the customer's links.
internal enum DeferredLinkContext {

    private static let prefsKey = "grivn_deferred_deeplink"
    private static let keyFirstLaunchChecked = "first_launch_checked"
    /// SDK 1.3.0 and earlier cached a device hash under this key. Nothing reads
    /// it; `removeLegacyData()` deletes it.
    private static let legacyKeyFingerprintId = "fingerprint_id"

    /// Checks whether this is the first launch (deferred deeplink not checked yet).
    static func isFirstLaunch() -> Bool {
        return !UserDefaults.standard.bool(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// Marks that the first-launch check has been performed.
    static func markFirstLaunchChecked() {
        UserDefaults.standard.set(true, forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// Resets the first-launch flag (for testing).
    static func resetFirstLaunch() {
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// Deletes data that older SDK versions stored and this version no longer uses.
    static func removeLegacyData() {
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(legacyKeyFingerprintId)")
    }

    /// Returns the current language code.
    static func getLanguage() -> String {
        return Locale.current.languageCode ?? "unknown"
    }

    /// Returns a default User-Agent string.
    @MainActor
    static func getUserAgent() -> String {
        let device = UIDevice.current
        let systemVersion = device.systemVersion.replacingOccurrences(of: ".", with: "_")
        let model = device.model
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        return "Mozilla/5.0 (\(model); CPU \(model) OS \(systemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) \(appName)/\(appVersion)"
    }
}
