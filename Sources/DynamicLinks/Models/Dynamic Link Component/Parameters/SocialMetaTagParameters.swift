import Foundation

public struct DynamicLinkSocialMetaTagParameters: Sendable, Codable {

    public var title: String?

    public var descriptionText: String?

    public var imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case title = "st"
        case descriptionText = "sd"
        case imageURL = "si"
    }

    public init(title: String? = nil, descriptionText: String? = nil, imageURL: URL? = nil) {
        self.title = title
        self.descriptionText = descriptionText
        self.imageURL = imageURL
    }
}
