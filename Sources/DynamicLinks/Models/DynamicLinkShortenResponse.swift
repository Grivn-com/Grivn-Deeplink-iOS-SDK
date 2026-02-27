//
//  DynamicLinkShortenResponse.swift
//  DynamicLinks
//

import Foundation

/// Response returned when shortening a dynamic link.
@objcMembers
public final class DynamicLinkShortenResponse: NSObject, Decodable, @unchecked Sendable {
    
    /// Link identifier.
    public let id: String
    
    /// Short link as a string.
    public let shortLinkString: String
    
    /// Original link URL string.
    public let link: String
    
    /// Optional link name.
    public let name: String?
    
    /// List of warning messages.
    public let warnings: [Warning]
    
    /// Short link as a `URL`.
    public var shortLink: URL? {
        URL(string: shortLinkString)
    }
    
    @objcMembers
    public final class Warning: NSObject, Decodable {
        public let warningCode: String
        public let warningMessage: String
        
        enum CodingKeys: String, CodingKey {
            case warningCode
            case warningMessage
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case shortLinkString = "short_link"
        case link
        case name
        case warnings
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        shortLinkString = try container.decode(String.self, forKey: .shortLinkString)
        link = try container.decode(String.self, forKey: .link)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        warnings = try container.decodeIfPresent([Warning].self, forKey: .warnings) ?? []
        super.init()
    }
}

