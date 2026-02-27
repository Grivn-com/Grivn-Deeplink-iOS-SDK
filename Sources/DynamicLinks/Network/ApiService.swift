//
//  ApiService.swift
//  DynamicLinks
//

import Foundation

/// Base API response type (backend may return only `data` without `code`/`message`).
internal struct BaseApiResponse<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
}

/// Request payload for creating a deeplink.
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

/// Request payload for resolving a short link.
internal struct ExchangeShortLinkRequest: Encodable {
    let requestedLink: String
}

/// Request payload for retrieving a deferred deeplink.
/// Note: `fingerprint_id` is not sent; the server generates it from IP + User-Agent.
internal struct DeferredDeeplinkRequest: Encodable {
    let user_agent: String
    let screen_resolution: String?
    let timezone: String?
    let language: String?
}

/// Response payload for a deferred deeplink.
internal struct DeferredDeeplinkResponse: Decodable {
    let found: Bool
    let link_data: [String: AnyCodable]?
}

/// Request payload for batching analytics events.
/// @unchecked Sendable: params contain only JSON-primitive values.
internal struct EventBatchRequest: Encodable, @unchecked Sendable {
    let projectId: String
    let deviceId: String
    let deviceType: String
    let osVersion: String
    let appVersion: String
    let sdkVersion: String
    let events: [EventItemRequest]

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case deviceId = "device_id"
        case deviceType = "device_type"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case sdkVersion = "sdk_version"
        case events
    }
}

/// Single analytics event within a batch.
/// @unchecked Sendable: params contain only JSON-primitive values.
internal struct EventItemRequest: Encodable, @unchecked Sendable {
    let eventName: String
    let params: [String: Any]?
    let timestamp: TimeInterval?
    let deeplinkId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case params
        case timestamp
        case deeplinkId = "deeplink_id"
        case userId = "user_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventName, forKey: .eventName)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(deeplinkId, forKey: .deeplinkId)
        try container.encode(userId, forKey: .userId)
        if let params = params {
            try container.encode(params.mapValues { AnyCodable($0) }, forKey: .params)
        }
    }
}

/// Response payload for a batched event submission.
internal struct EventBatchResponse: Decodable {
    let accepted: Int
}

/// Request payload for confirming an install.
/// Note: `fingerprint_id` is not sent; the server generates it from IP + User-Agent.
internal struct ConfirmInstallRequest: Encodable {
    let user_agent: String
    let device_model: String?
    let os_version: String?
    let app_version: String?
}

/// Response payload for confirming an install.
internal struct ConfirmInstallResponse: Decodable {
    let success: Bool
    let message: String?
}

/// Helper wrapper used to decode arbitrary JSON values.
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

/// API service used by the SDK.
/// Authentication is done via the `X-API-Key` header.
internal final class ApiService: Sendable {

    private let baseUrl: String
    private let secretKey: String
    private let session: URLSession

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

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        if trustAllCerts {
            self.session = URLSession(configuration: configuration, delegate: TrustAllCertsDelegate(), delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: configuration)
        }
    }
    
    /// Creates a short link from the given components.
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
    
    /// Resolves a short link back to its long-link representation.
    func exchangeShortLink(requestedLink: URL) async throws -> ExchangeLinkResponse {
        let url = URL(string: "\(baseUrl)/api/v1/deeplinks/exchangeShortLink")!
        
        let body = ExchangeShortLinkRequest(requestedLink: requestedLink.absoluteString)
        
        return try await post(url: url, body: body)
    }
    
    /// Retrieves a deferred deeplink.
    /// The server performs fingerprint matching based on IP + User-Agent.
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
    
    /// Sends a batch of SDK events.
    func trackEvents(request: EventBatchRequest) async throws -> EventBatchResponse {
        let url = URL(string: "\(baseUrl)/api/v1/events")!
        return try await post(url: url, body: request)
    }

    /// Confirms an install.
    /// The server performs fingerprint matching based on IP + User-Agent.
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
    
    /// Issues a POST request and decodes the response.
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

        // Prefer decoding the wrapped `code`/`data` format first.
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

        // Fallback: support backend responses that return the bare `data` object without wrapping.
        if let direct = try? decoder.decode(R.self, from: data) {
            return direct
        }

        SDKLogger.error("Response parse error — failed to decode response body")
        throw DynamicLinksSDKError.parseError(message: "Missing data in response", cause: nil)
    }
}

/// Delegate that trusts all certificates (development only).
/// @unchecked Sendable: stateless delegate, safe to share across threads.
private final class TrustAllCertsDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
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

