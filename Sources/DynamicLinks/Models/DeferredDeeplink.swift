//
//  DeferredDeeplink.swift
//  DynamicLinks
//
//  Deferred Deeplink 数据模型和工具类
//

import UIKit
import CommonCrypto

/// Deferred Deeplink 数据
///
/// 当用户通过 Deeplink 跳转到 App Store 下载 App，首次打开时可以获取原始链接数据
/// @unchecked Sendable: all properties are `let` and contain only JSON-primitive values
@objc public class DeferredDeeplinkData: NSObject, @unchecked Sendable {

    /// 是否找到延迟深链
    @objc public let found: Bool

    /// 原始链接数据
    @objc public let linkData: [String: Any]?

    /// 获取原始 Deeplink ID
    @objc public var deeplinkId: String? {
        return linkData?["deeplink_id"] as? String
    }

    /// 获取 Project ID
    @objc public var projectId: String? {
        return linkData?["project_id"] as? String
    }

    /// 获取原始 URL
    @objc public var originalUrl: String? {
        return linkData?["original_url"] as? String
    }

    /// 获取 UTM Source
    @objc public var utmSource: String? {
        return linkData?["utm_source"] as? String
    }

    /// 获取 UTM Medium
    @objc public var utmMedium: String? {
        return linkData?["utm_medium"] as? String
    }

    /// 获取 UTM Campaign
    @objc public var utmCampaign: String? {
        return linkData?["utm_campaign"] as? String
    }

    /// 获取 Referer
    @objc public var referer: String? {
        return linkData?["referer"] as? String
    }

    /// 获取自定义数据
    @objc public func getCustomData(key: String) -> Any? {
        return linkData?[key]
    }

    init(found: Bool, linkData: [String: Any]?) {
        self.found = found
        self.linkData = linkData
        super.init()
    }
}

/// 设备指纹生成器
///
/// 用于生成设备唯一标识，匹配 Deferred Deeplink
internal class DeviceFingerprint {

    private static let prefsKey = "grivn_deferred_deeplink"
    private static let keyFirstLaunchChecked = "first_launch_checked"
    private static let keyFingerprintId = "fingerprint_id"

    /// 获取或生成设备指纹
    @MainActor
    static func getFingerprint() -> String {
        // 优先使用缓存的指纹
        if let cached = UserDefaults.standard.string(forKey: "\(prefsKey).\(keyFingerprintId)") {
            return cached
        }

        // 生成新指纹
        let fingerprint = generateFingerprint()
        UserDefaults.standard.set(fingerprint, forKey: "\(prefsKey).\(keyFingerprintId)")

        return fingerprint
    }

    /// 检查是否是首次启动（未检查过 Deferred Deeplink）
    static func isFirstLaunch() -> Bool {
        return !UserDefaults.standard.bool(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// 标记已检查过首次启动
    static func markFirstLaunchChecked() {
        UserDefaults.standard.set(true, forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// 重置首次启动标记（用于测试）
    static func resetFirstLaunch() {
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
    }

    /// 清除所有缓存数据（用于测试）
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFirstLaunchChecked)")
        UserDefaults.standard.removeObject(forKey: "\(prefsKey).\(keyFingerprintId)")
    }

    /// 生成设备指纹
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

    /// 获取设备类型
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

    /// 获取屏幕分辨率
    @MainActor
    static func getScreenResolution() -> String {
        let screen = UIScreen.main
        let scale = screen.scale
        let bounds = screen.bounds
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        return "\(width)x\(height)"
    }

    /// 获取时区
    static func getTimezone() -> String {
        return TimeZone.current.identifier
    }

    /// 获取语言
    static func getLanguage() -> String {
        return Locale.current.languageCode ?? "unknown"
    }

    /// 获取 User-Agent
    @MainActor
    static func getUserAgent() -> String {
        let device = UIDevice.current
        let systemVersion = device.systemVersion.replacingOccurrences(of: ".", with: "_")
        let model = device.model
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        return "Mozilla/5.0 (\(model); CPU \(model) OS \(systemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) \(appName)/\(appVersion)"
    }

    /// SHA256 哈希
    private static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
