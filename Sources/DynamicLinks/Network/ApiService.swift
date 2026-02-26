//
//  ApiService.swift
//  DynamicLinks
//

import Foundation

/// API 请求响应基类（后端可能只返回 data，无 code/message）
internal struct BaseApiResponse<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
}

/// 创建 Deeplink 请求
internal struct DeeplinkCreateRequest: Encodable {
    let projectId: String
    let name: String
    let link: String
    // Android Parameters
    let apn: String?
    let afl: String?
    let amv: String?
    // iOS Parameters
    let ibi: String?
    let ifl: String?
    let ius: String?
    let ipfl: String?
    let ipbi: String?
    let isi: String?
    let imv: String?
    let efr: Bool?
    // Other Platform
    let ofl: String?
    // Social Meta Tags
    let st: String?
    let sd: String?
    let si: String?
    // Analytics (UTM)
    let utm_source: String?
    let utm_medium: String?
    let utm_campaign: String?
    let utm_content: String?
    let utm_term: String?
    // iTunes Connect
    let at: String?
    let ct: String?
    let mt: String?
    let pt: String?
}

/// 解析短链接请求
internal struct ExchangeShortLinkRequest: Encodable {
    let requestedLink: String
}

/// 获取延迟深链请求
/// 注意：不发送 fingerprint_id，服务端会根据 IP + UserAgent 自动生成
internal struct DeferredDeeplinkRequest: Encodable {
    let user_agent: String
    let screen_resolution: String?
    let timezone: String?
    let language: String?
}

/// 延迟深链响应
internal struct DeferredDeeplinkResponse: Decodable {
    let found: Bool
    let link_data: [String: AnyCodable]?
}

/// 确认安装请求
/// 注意：不发送 fingerprint_id，服务端会根据 IP + UserAgent 自动生成
internal struct ConfirmInstallRequest: Encodable {
    let user_agent: String
    let device_model: String?
    let os_version: String?
    let app_version: String?
}

/// 确认安装响应
internal struct ConfirmInstallResponse: Decodable {
    let success: Bool
    let message: String?
}

/// 用于解码任意 JSON 值
internal struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unable to encode value"))
        }
    }
}

/// API 服务类
/// 通过 X-API-Key header 进行认证
internal final class ApiService: @unchecked Sendable {
    
    private let baseUrl: String
    private let secretKey: String
    private let timeout: TimeInterval
    private let trustAllCerts: Bool
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        
        if trustAllCerts {
            // 开发环境：信任所有证书
            return URLSession(configuration: configuration, delegate: TrustAllCertsDelegate(), delegateQueue: nil)
        }
        
        return URLSession(configuration: configuration)
    }()
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
    
    init(
        baseUrl: String,
        secretKey: String,
        timeout: TimeInterval = 30,
        trustAllCerts: Bool = false
    ) {
        self.baseUrl = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        self.secretKey = secretKey
        self.timeout = timeout
        self.trustAllCerts = trustAllCerts
    }
    
    /// 创建短链接 (缩短链接)
    func shortenUrl(
        projectId: String,
        components: DynamicLinkComponents
    ) async throws -> DynamicLinkShortenResponse {
        let url = URL(string: "\(baseUrl)/api/v1/deeplinks")!
        
        let body = DeeplinkCreateRequest(
            projectId: projectId,
            name: components.link.absoluteString,
            link: components.link.absoluteString,
            // Android Parameters
            apn: components.androidParameters?.packageName,
            afl: components.androidParameters?.fallbackURL?.absoluteString,
            amv: components.androidParameters?.minimumVersion != nil ? String(components.androidParameters!.minimumVersion) : nil,
            // iOS Parameters
            ibi: nil,
            ifl: components.iOSParameters.fallbackURL?.absoluteString,
            ius: nil,
            ipfl: components.iOSParameters.iPadFallbackURL?.absoluteString,
            ipbi: nil,
            isi: components.iOSParameters.appStoreID,
            imv: components.iOSParameters.minimumAppVersion,
            efr: nil,
            // Other Platform
            ofl: components.otherPlatformParameters?.fallbackURL?.absoluteString,
            // Social Meta Tags
            st: components.socialMetaTagParameters?.title,
            sd: components.socialMetaTagParameters?.descriptionText,
            si: components.socialMetaTagParameters?.imageURL?.absoluteString,
            // Analytics (UTM)
            utm_source: components.analyticsParameters?.source,
            utm_medium: components.analyticsParameters?.medium,
            utm_campaign: components.analyticsParameters?.campaign,
            utm_content: components.analyticsParameters?.content,
            utm_term: components.analyticsParameters?.term,
            // iTunes Connect
            at: components.iTunesConnectParameters?.affiliateToken,
            ct: components.iTunesConnectParameters?.campaignToken,
            mt: nil,
            pt: components.iTunesConnectParameters?.providerToken
        )
        
        return try await post(url: url, body: body)
    }
    
    /// 解析短链接 (还原长链接)
    func exchangeShortLink(requestedLink: URL) async throws -> ExchangeLinkResponse {
        let url = URL(string: "\(baseUrl)/api/v1/deeplinks/exchangeShortLink")!
        
        let body = ExchangeShortLinkRequest(requestedLink: requestedLink.absoluteString)
        
        return try await post(url: url, body: body)
    }
    
    /// 获取延迟深链
    /// 服务端会根据请求的 IP + UserAgent 生成指纹进行匹配
    func getDeferredDeeplink(
        userAgent: String,
        screenResolution: String?,
        timezone: String?,
        language: String?
    ) async throws -> DeferredDeeplinkResponse {
        let url = URL(string: "\(baseUrl)/api/v1/analytics/deferred")!
        
        let body = DeferredDeeplinkRequest(
            user_agent: userAgent,
            screen_resolution: screenResolution,
            timezone: timezone,
            language: language
        )
        
        return try await post(url: url, body: body)
    }
    
    /// 确认安装
    /// 服务端会根据请求的 IP + UserAgent 生成指纹进行匹配
    func confirmInstall(
        userAgent: String,
        deviceModel: String?,
        osVersion: String?,
        appVersion: String?
    ) async throws -> ConfirmInstallResponse {
        let url = URL(string: "\(baseUrl)/api/v1/analytics/confirm-install")!
        
        let body = ConfirmInstallRequest(
            user_agent: userAgent,
            device_model: deviceModel,
            os_version: osVersion,
            app_version: appVersion
        )
        
        return try await post(url: url, body: body)
    }
    
    /// POST 请求
    private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(secretKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        SDKLogger.debug("→ POST \(url) [key=\(SDKLogger.maskApiKey(secretKey))]")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            SDKLogger.error("Network I/O error: \(error.localizedDescription)", error)
            throw DynamicLinksSDKError.networkError(message: "Network error: \(error.localizedDescription)", cause: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            SDKLogger.error("Invalid response (not HTTP)")
            throw DynamicLinksSDKError.networkError(message: "Invalid response", cause: nil)
        }

        SDKLogger.debug("← \(httpResponse.statusCode) (\(data.count) bytes)")

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            SDKLogger.error("HTTP error \(httpResponse.statusCode)")
            throw DynamicLinksSDKError.networkError(message: "Server error: \(httpResponse.statusCode)", cause: nil)
        }

        guard !data.isEmpty else {
            SDKLogger.error("Empty response body")
            throw DynamicLinksSDKError.networkError(message: "Empty response", cause: nil)
        }

        // 优先尝试带 code/data 包装
        if let wrapped = try? decoder.decode(BaseApiResponse<R>.self, from: data) {
            let status = wrapped.code ?? 0
            if status != 0 {
                SDKLogger.error("Server error code=\(status): \(wrapped.message ?? "")")
                throw DynamicLinksSDKError.serverError(message: wrapped.message ?? "Server error", code: status)
            }
            if let payload = wrapped.data {
                return payload
            }
        }

        // 兼容后端直接返回 data 对象（无包装）
        if let direct = try? decoder.decode(R.self, from: data) {
            return direct
        }

        SDKLogger.error("Response parse error — failed to decode response body")
        throw DynamicLinksSDKError.parseError(message: "Missing data in response", cause: nil)
    }
}

/// 信任所有证书的代理 (仅开发环境使用)
private final class TrustAllCertsDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

