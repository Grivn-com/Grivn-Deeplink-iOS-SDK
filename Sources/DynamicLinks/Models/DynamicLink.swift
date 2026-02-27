//
//  DynamicLink.swift
//  DynamicLinks
//

import Foundation

/// Represents a parsed dynamic link.
/// Responsible for extracting the deep link, UTM parameters, and minimum app version from a long link.
@objc
public final class DynamicLink: NSObject, @unchecked Sendable {
    
    /// Extracted deep link URL.
    @objc public let url: URL?
    
    /// UTM parameters extracted from the long link, used for tracking.
    @objc public let utmParameters: [String: String]
    
    /// Minimum app version that can open this link (from the `"imv"` parameter, iOS-only).
    @objc public let minimumAppVersion: String?
    
    /// Initializes a `DynamicLink` from the long link.
    ///
    /// - Parameter longLink: Long URL containing the dynamic link and UTM parameters.
    @objc public init?(longLink: URL) {
        guard let components = URLComponents(url: longLink, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            SDKLogger.warn("Invalid long link URL")
            return nil
        }
        
        // Extract the deep link.
        let deepLink = queryItems.first(where: { $0.name == "link" })?.value.flatMap(URL.init)
        
        // Extract the minimum iOS version (imv).
        let imv = queryItems.first(where: { $0.name == "imv" })?.value
        
        // Extract all UTM parameters.
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
