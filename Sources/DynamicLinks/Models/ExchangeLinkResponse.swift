//
//  ExchangeLinkResponse.swift
//  DynamicLinks
//

import Foundation

/// 解析短链接的响应
/// 后端返回的是 URL query parameters，SDK 将其组装成长链接
public struct ExchangeLinkResponse: Decodable, Sendable {
    // 后端返回的各个参数字段
    public let link: String?
    public let apn: String?
    public let afl: String?
    public let amv: String?
    public let ibi: String?
    public let ifl: String?
    public let ius: String?
    public let ipfl: String?
    public let ipbi: String?
    public let isi: String?
    public let imv: String?
    public let efr: String?
    public let ofl: String?
    public let st: String?
    public let sd: String?
    public let si: String?
    public let utm_source: String?
    public let utm_medium: String?
    public let utm_campaign: String?
    public let utm_content: String?
    public let utm_term: String?
    public let at: String?
    public let ct: String?
    public let mt: String?
    public let pt: String?
    
    /// 将后端返回的参数组装成长链接 URL
    public var longLink: URL? {
        guard let baseLink = link else { return nil }
        
        var components = URLComponents(string: "https://dynamiclinks.local")
        var queryItems: [URLQueryItem] = []
        
        // 添加所有非空参数
        queryItems.append(URLQueryItem(name: "link", value: baseLink))
        if let apn = apn { queryItems.append(URLQueryItem(name: "apn", value: apn)) }
        if let afl = afl { queryItems.append(URLQueryItem(name: "afl", value: afl)) }
        if let amv = amv { queryItems.append(URLQueryItem(name: "amv", value: amv)) }
        if let ibi = ibi { queryItems.append(URLQueryItem(name: "ibi", value: ibi)) }
        if let ifl = ifl { queryItems.append(URLQueryItem(name: "ifl", value: ifl)) }
        if let ius = ius { queryItems.append(URLQueryItem(name: "ius", value: ius)) }
        if let ipfl = ipfl { queryItems.append(URLQueryItem(name: "ipfl", value: ipfl)) }
        if let ipbi = ipbi { queryItems.append(URLQueryItem(name: "ipbi", value: ipbi)) }
        if let isi = isi { queryItems.append(URLQueryItem(name: "isi", value: isi)) }
        if let imv = imv { queryItems.append(URLQueryItem(name: "imv", value: imv)) }
        if let efr = efr { queryItems.append(URLQueryItem(name: "efr", value: efr)) }
        if let ofl = ofl { queryItems.append(URLQueryItem(name: "ofl", value: ofl)) }
        if let st = st { queryItems.append(URLQueryItem(name: "st", value: st)) }
        if let sd = sd { queryItems.append(URLQueryItem(name: "sd", value: sd)) }
        if let si = si { queryItems.append(URLQueryItem(name: "si", value: si)) }
        if let utm_source = utm_source { queryItems.append(URLQueryItem(name: "utm_source", value: utm_source)) }
        if let utm_medium = utm_medium { queryItems.append(URLQueryItem(name: "utm_medium", value: utm_medium)) }
        if let utm_campaign = utm_campaign { queryItems.append(URLQueryItem(name: "utm_campaign", value: utm_campaign)) }
        if let utm_content = utm_content { queryItems.append(URLQueryItem(name: "utm_content", value: utm_content)) }
        if let utm_term = utm_term { queryItems.append(URLQueryItem(name: "utm_term", value: utm_term)) }
        if let at = at { queryItems.append(URLQueryItem(name: "at", value: at)) }
        if let ct = ct { queryItems.append(URLQueryItem(name: "ct", value: ct)) }
        if let mt = mt { queryItems.append(URLQueryItem(name: "mt", value: mt)) }
        if let pt = pt { queryItems.append(URLQueryItem(name: "pt", value: pt)) }
        
        components?.queryItems = queryItems
        return components?.url
    }
}
