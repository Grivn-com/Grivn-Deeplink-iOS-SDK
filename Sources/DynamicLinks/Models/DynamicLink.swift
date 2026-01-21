//
//  DynamicLink.swift
//  DynamicLinks
//

import Foundation

/// 表示一个解析后的动态链接
/// 负责从长链接中提取深度链接、UTM 参数和最低 App 版本要求
@objc
public final class DynamicLink: NSObject, @unchecked Sendable {
    
    /// 提取的深度链接 URL
    @objc public let url: URL?
    
    /// 从长链接中提取的 UTM 参数，用于追踪目的
    @objc public let utmParameters: [String: String]
    
    /// 能够打开此链接的最低 App 版本 (从 "imv" 参数提取，iOS 特有)
    @objc public let minimumAppVersion: String?
    
    /// 从长链接初始化 DynamicLink
    ///
    /// - Parameter longLink: 包含动态链接和 UTM 参数的长 URL
    @objc public init?(longLink: URL) {
        guard let components = URLComponents(url: longLink, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            print("❌ Invalid long link URL")
            return nil
        }
        
        // 提取深度链接
        let deepLink = queryItems.first(where: { $0.name == "link" })?.value.flatMap(URL.init)
        
        // 提取 iOS 最低版本 (imv)
        let imv = queryItems.first(where: { $0.name == "imv" })?.value
        
        // 提取所有 UTM 参数
        var utmParams = [String: String]()
        for item in queryItems where item.name.starts(with: "utm_") {
            if let value = item.value {
                utmParams[item.name] = value
            }
        }
        
        self.url = deepLink
        self.utmParameters = utmParams
        self.minimumAppVersion = imv
    }
}
