import Foundation

@objcMembers
public final class DynamicLinkAnalyticsParameters: NSObject, @unchecked Sendable, Codable {

    /// The UTM source (e.g., google, newsletter).
    public var source: String?

    /// The UTM medium (e.g., cpc, email).
    public var medium: String?

    /// The UTM campaign name.
    public var campaign: String?

    /// The UTM term (e.g., paid keywords).
    public var term: String?

    /// The UTM content (e.g., banner_ad).
    public var content: String?

    enum CodingKeys: String, CodingKey {
        case source = "utm_source"
        case medium = "utm_medium"
        case campaign = "utm_campaign"
        case term = "utm_term"
        case content = "utm_content"
    }

    public init(
        source: String? = nil,
        medium: String? = nil,
        campaign: String? = nil,
        term: String? = nil,
        content: String? = nil
    ) {
        self.source = source
        self.medium = medium
        self.campaign = campaign
        self.term = term
        self.content = content
    }
}
