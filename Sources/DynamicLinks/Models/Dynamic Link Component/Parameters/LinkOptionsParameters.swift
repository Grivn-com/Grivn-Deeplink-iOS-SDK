import Foundation

@objc public final class DynamicLinkOptionsParameters: NSObject, Codable, @unchecked Sendable {

    @objc
    public enum DynamicLinkPathLength: Int, Codable, @unchecked Sendable {
        case unguessable = 0
        case short = 1
    }

    @objc public var pathLength: DynamicLinkPathLength

    @objc
    public init(pathLength: DynamicLinkPathLength = .unguessable) {
        self.pathLength = pathLength
    }

}
