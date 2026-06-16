import Foundation

/// Options for a Dynamic Link, currently the path mode (GRIVN-2).
///
/// The value is sent to the backend as the `pathMode` field of the create
/// request (NOT a query parameter on the link); the backend mints the short
/// code accordingly. Leave the component's `options` as `nil` to take the
/// backend default (UNGUESSABLE).
@objc public final class DynamicLinkOptionsParameters: NSObject, Codable, @unchecked Sendable {

    /// The short-code generation mode for a Dynamic Link.
    ///
    /// - `unguessable`: a long, always-unique code that is hard to enumerate
    ///   (auth / per-user links). Backend default.
    /// - `short`: a short, deduped code — creating again with identical
    ///   parameters returns the same code (shareable, non-user-specific content).
    @objc
    public enum DynamicLinkPathLength: Int, Codable, @unchecked Sendable {
        case unguessable = 0
        case short = 1

        /// The wire value sent as `pathMode` in the create request.
        public var pathMode: String {
            switch self {
            case .short: return "SHORT"
            case .unguessable: return "UNGUESSABLE"
            }
        }
    }

    @objc public var pathLength: DynamicLinkPathLength

    @objc
    public init(pathLength: DynamicLinkPathLength = .unguessable) {
        self.pathLength = pathLength
    }
}
