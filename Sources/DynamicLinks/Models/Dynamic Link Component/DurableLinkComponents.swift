import Foundation

@objc
public final class DynamicLinkComponents: NSObject, @unchecked Sendable {

    /// Target deep link URL.
    public let link: URL
    
    /// Short link domain URI prefix.
    public let domainUriPrefix: String

    public var iOSParameters: DynamicLinkIOSParameters = DynamicLinkIOSParameters()
    public var androidParameters: DynamicLinkAndroidParameters?
    public var iTunesConnectParameters: DynamicLinkItunesConnectAnalyticsParameters?
    public var socialMetaTagParameters: DynamicLinkSocialMetaTagParameters?
    public var otherPlatformParameters: DynamicLinkOtherPlatformParameters?
    public var analyticsParameters: DynamicLinkAnalyticsParameters?

    public init?(
        link: URL,
        domainURIPrefix: String,
        iOSParameters: DynamicLinkIOSParameters = DynamicLinkIOSParameters(),
        androidParameters: DynamicLinkAndroidParameters? = nil,
        iTunesConnectParameters: DynamicLinkItunesConnectAnalyticsParameters? = nil,
        socialMetaTagParameters: DynamicLinkSocialMetaTagParameters? = nil,
        otherPlatformParameters: DynamicLinkOtherPlatformParameters? = nil,
        analyticsParameters: DynamicLinkAnalyticsParameters? = nil
    ) {
        self.link = link

        guard let domainURIPrefixURL = URL(string: domainURIPrefix) else {
            SDKLogger.warn("Invalid domainURIPrefix. Please input a valid URL.")
            return nil
        }
        guard domainURIPrefixURL.scheme?.lowercased() == "https" else {
            SDKLogger.warn("Invalid domainURIPrefix scheme. Scheme needs to be https.")
            return nil
        }

        self.domainUriPrefix = domainURIPrefix
        self.iOSParameters = iOSParameters
        self.androidParameters = androidParameters
        self.iTunesConnectParameters = iTunesConnectParameters
        self.socialMetaTagParameters = socialMetaTagParameters
        self.otherPlatformParameters = otherPlatformParameters
        self.analyticsParameters = analyticsParameters
    }

    public var url: URL? {
        let queryString = buildQueryDict().compactMap { key, value in
            guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else {
                return nil
            }
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")

        return URL(string: "\(domainUriPrefix)/?\(queryString)")
    }

    private func buildQueryDict() -> [String: String] {
        var dict: [String: String] = ["link": link.absoluteString]

        let addParams = { (params: Encodable?) in
            guard let encodable = params,
                let data = try? JSONEncoder().encode(encodable),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }
            for (key, value) in json {
                if let stringValue = value as? String {
                    dict[key] = stringValue
                } else if let numberValue = value as? NSNumber {
                    dict[key] = numberValue.stringValue
                }
            }
        }

        addParams(analyticsParameters)
        addParams(socialMetaTagParameters)
        addParams(iOSParameters)
        addParams(androidParameters)
        addParams(iTunesConnectParameters)
        addParams(otherPlatformParameters)

        return dict
    }
}
