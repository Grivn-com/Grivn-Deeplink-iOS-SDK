//
//  DeferredDeeplink.swift
//  DynamicLinks
//
//  Deferred deeplink data model and helper utilities.
//

import UIKit
import CommonCrypto

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

/// Device fingerprint generator.
///
/// Used to generate a device identifier for matching deferred deeplinks.
internal class DeviceFingerprint {

    private static let prefsKey = "grivn_deferred_deeplink"
    private static let keyFirstLaunchChecked = "first_launch_checked"
    private static let keyFingerprintId = "fingerprint_id"

    /// Returns the stored device fingerprint or generates a new one.
    @MainActor
    static func getFingerprint() -> String {
        // Prefer using the cached fingerprint if available.
        if let cached = UserDefaults.standard.string(forKey: "\(prefsKey).\(keyFingerprintId)") {
            return cached
        }

        // Generate a new fingerprint.
        let fingerprint = generateFingerprint()
        UserDefaults.standard.set(fingerprint, forKey: "\(prefsKey).\(keyFingerprintId)")

        return fingerprint
    }

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

    /// Clears all cached data (for testing).
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFingerprintId)")
    }

    /// Generates a device fingerprint.
    @MainActor
    private static func generateFingerprint() -> String {
        let components = [
            getDeviceType(),
            "ios",
            UIDevice.current.model,
            UIDevice.current.systemVersion
        ]

        let data = components.joined(separator: "|")
        return sha256(data)
    }

    /// Returns the device type.
    @MainActor
    private static func getDeviceType() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "tablet"
        case .phone:
            return "mobile"
        default:
            return "mobile"
        }
    }

    /// Returns the screen resolution.
    @MainActor
    static func getScreenResolution() -> String {
        let screen = UIScreen.main
        let scale = screen.scale
        let bounds = screen.bounds
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        return "\(width)x\(height)"
    }

    /// Returns the current timezone identifier.
    static func getTimezone() -> String {
        return TimeZone.current.identifier
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

    /// Computes a SHA256 hash.
    private static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
