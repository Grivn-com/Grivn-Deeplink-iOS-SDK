import Testing
import Foundation
@testable import DynamicLinks

/// Smoke tests for the core client-facing logic: long-link parsing, the
/// client-side URL builder, and deferred-deeplink result accessors. These build
/// and run under `xcodebuild test` on an iOS Simulator (a real Apple environment,
/// so UIKit/CommonCrypto are available).
@Suite struct DynamicLinksSmokeTests {

    @Test func parsesLongLinkFields() throws {
        let deep = "https://app.example.com/welcome"
        let encoded = deep.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let long = URL(string: "https://x.grivn.com/abc?link=\(encoded)&imv=1.3.0&utm_source=google&utm_medium=cpc")!

        let dl = try #require(DynamicLink(longLink: long))
        #expect(dl.url == URL(string: deep))
        #expect(dl.minimumAppVersion == "1.3.0")
        #expect(dl.utmParameters["utm_source"] == "google")
        #expect(dl.utmParameters["utm_medium"] == "cpc")
    }

    @Test func returnsNilForLinkWithoutQuery() {
        #expect(DynamicLink(longLink: URL(string: "https://x.grivn.com/abc")!) == nil)
    }

    @Test func componentsBuildsUrlAndValidatesHttpsPrefix() throws {
        let link = URL(string: "https://app.example.com/page")!

        let components = try #require(
            DynamicLinkComponents(link: link, domainURIPrefix: "https://x.grivn.com")
        )
        let url = try #require(components.url)
        #expect(url.absoluteString.contains("link="))

        // Non-https prefix -> failable init returns nil.
        #expect(DynamicLinkComponents(link: link, domainURIPrefix: "http://x.grivn.com") == nil)
    }

    @Test func deferredDeeplinkDataReadsFields() {
        let data = DeferredDeeplinkData(found: true, linkData: [
            "deeplink_id": "dl_abc",
            "utm_source": "newsletter",
            "custom_key": "custom_value"
        ])
        #expect(data.found)
        #expect(data.deeplinkId == "dl_abc")
        #expect(data.utmSource == "newsletter")
        #expect(data.getCustomData(key: "custom_key") as? String == "custom_value")

        let empty = DeferredDeeplinkData(found: false, linkData: nil)
        #expect(empty.deeplinkId == nil)
        #expect(empty.getCustomData(key: "x") == nil)
    }
}
