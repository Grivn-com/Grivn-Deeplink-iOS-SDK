//
//  DynamicLinkShortenResponse.swift
//  DynamicLinks
//

import Foundation

/// 缩短链接的响应
@objcMembers
public final class DynamicLinkShortenResponse: NSObject, Decodable, @unchecked Sendable {
    
    /// 链接 ID
    public let id: String
    
    /// 短链接字符串
    public let shortLinkString: String
    
    /// 原始链接
    public let link: String
    
    /// 链接名称
    public let name: String?
    
    /// 警告信息列表
    public let warnings: [Warning]
    
    /// 短链接 URL
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

