import Foundation

@objc
public final class DynamicLinkComponents: NSObject, @unchecked Sendable {

    /// 目标深度链接 URL
    public let link: URL
    
    /// 短链接域名前缀
    public let domainUriPrefix: String

    public var iOSParameters: DynamicLinkIOSParameters = DynamicLinkIOSParameters()
    public var androidParameters: DynamicLinkAndroidParameters?
    public var iTunesConnectParameters: DynamicLinkItunesConnectAnalyticsParameters?
    public var socialMetaTagParameters: DynamicLinkSocialMetaTagParameters?
    public var options: DynamicLinkOptionsParameters = DynamicLinkOptionsParameters()
    public var otherPlatformParameters: DynamicLinkOtherPlatformParameters?
    public var analyticsParameters: DynamicLinkAnalyticsParameters?

    public init?(
        link: URL,
        domainURIPrefix: String,
        iOSParameters: DynamicLinkIOSParameters = DynamicLinkIOSParameters(),
        androidParameters: DynamicLinkAndroidParameters? = nil,
        iTunesConnectParameters: DynamicLinkItunesConnectAnalyticsParameters? = nil,
        socialMetaTagParameters: DynamicLinkSocialMetaTagParameters? = nil,
        options: DynamicLinkOptionsParameters = DynamicLinkOptionsParameters(),
        otherPlatformParameters: DynamicLinkOtherPlatformParameters? = nil,
        analyticsParameters: DynamicLinkAnalyticsParameters? = nil
    ) {
        self.link = link

        guard let domainURIPrefixURL = URL(string: domainURIPrefix) else {
            print("Invalid domainURIPrefix. Please input a valid URL.")
            return nil
        }
        guard domainURIPrefixURL.scheme?.lowercased() == "https" else {
            print("Invalid domainURIPrefix scheme. Scheme needs to be https.")
            return nil
        }

        self.domainUriPrefix = domainURIPrefix
        self.iOSParameters = iOSParameters
        self.androidParameters = androidParameters
        self.iTunesConnectParameters = iTunesConnectParameters
        self.socialMetaTagParameters = socialMetaTagParameters
        self.options = options
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
                if key == "pathLength" {
                    if let numberValue = value as? NSNumber {
                        let stringValue: String
                        switch numberValue.intValue {
                        case 1: stringValue = "SHORT"
                        default: stringValue = "UNGUESSABLE"
                        }
                        dict[key] = stringValue
                    }
                } else {
                    if let stringValue = value as? String {
                        dict[key] = stringValue
                    } else if let numberValue = value as? NSNumber {
                        dict[key] = numberValue.stringValue
                    }
                }
            }
        }

        addParams(analyticsParameters)
        addParams(socialMetaTagParameters)
        addParams(iOSParameters)
        addParams(androidParameters)
        addParams(iTunesConnectParameters)
        addParams(otherPlatformParameters)
        addParams(options)

        return dict
    }
}
