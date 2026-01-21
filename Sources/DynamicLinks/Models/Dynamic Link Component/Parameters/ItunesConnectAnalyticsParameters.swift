import Foundation

@objc
public final class DynamicLinkItunesConnectAnalyticsParameters: NSObject, @unchecked Sendable, Codable {

    /// The iTunes Connect affiliate token.
    @objc public var affiliateToken: String?

    /// The iTunes Connect campaign token.
    @objc public var campaignToken: String?

    /// The iTunes Connect provider token.
    @objc public var providerToken: String?

    enum CodingKeys: String, CodingKey {
        case affiliateToken = "at"
        case campaignToken = "ct"
        case providerToken = "pt"
    }

    @objc
    public init(affiliateToken: String? = nil, campaignToken: String? = nil, providerToken: String? = nil) {
        self.affiliateToken = affiliateToken
        self.campaignToken = campaignToken
        self.providerToken = providerToken
    }

}
