import Foundation

@objcMembers
public final class DynamicLinkAndroidParameters: NSObject, @unchecked Sendable, Codable {

    /// The Android app's package name.
    public let packageName: String

    /// The link to open when the app isn't installed.
    public var fallbackURL: URL?

    /// The version code of the minimum version of the app that can open the link.
    public var minimumVersion: Int = 0

    enum CodingKeys: String, CodingKey {
        case packageName = "apn"
        case fallbackURL = "afl"
        case minimumVersion = "amv"
    }

    /// Initializes the Android parameters with a required package name.
    public init(packageName: String, fallbackURL: URL? = nil, minimumVersion: Int = 0) {
        self.packageName = packageName
        self.fallbackURL = fallbackURL
        self.minimumVersion = minimumVersion
    }

}
