# DynamicLinks-iOS

iOS SDK for handling Dynamic Links with Grivn backend.

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Grivn-com/Grivn-Deeplink-iOS-SDK.git", from: "1.3.0")
]
```

Or add it via Xcode: File → Add Packages → Enter the repository URL.

## Quick Start

### 1. Initialize the SDK

Call `DynamicLinksSDK.initialize()` in your AppDelegate or before using any SDK features:

```swift
import DynamicLinks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize SDK
        DynamicLinksSDK.initialize(
            baseUrl: "https://api.grivn.com",    // Backend API URL
            secretKey: "your_secret_key",         // X-API-Key for authentication
            projectId: "your_project_id"          // Project ID for creating links
        )
        
        // Configure allowed hosts for link validation
        DynamicLinksSDK.configure(allowedHosts: ["YOUR_PROJECT_ID.grivn.com"])
        
        return true
    }
}
```

### 2. Handle Dynamic Links

> **Required for Universal Links to reach your app:** add an Associated Domains
> entitlement `applinks:YOUR_PROJECT_ID.grivn.com` (Signing & Capabilities) and
> set your iOS App ID in the Grivn dashboard. The backend auto-serves
> `/.well-known/apple-app-site-association`. Without this, iOS never delivers the
> link to the SDK. Full setup with copy-paste examples: **Developer Tools → SDK
> Docs** in your Grivn dashboard.
>
> **Deferred deep links on iOS** are resolved by probabilistic matching on
> network and device signals: there is no iOS equivalent of Android's Play
> Install Referrer, so `match_tier` is always `"fingerprint"`. Read
> [Privacy & App Review](#privacy--app-review) before you ship.

Handle incoming dynamic links in your SceneDelegate or AppDelegate:

```swift
import DynamicLinks

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let incomingURL = userActivity.webpageURL else { return }
        
        Task {
            do {
                let dynamicLink = try await DynamicLinksSDK.shared.handleDynamicLink(incomingURL)
                
                // Get the deep link URL
                let deepLink = dynamicLink.url
                
                // Get UTM parameters
                let utmSource = dynamicLink.utmParameters["utm_source"]
                
                // Get minimum app version
                let minVersion = dynamicLink.minimumAppVersion
                
                // Navigate based on the deep link
                handleDeepLink(deepLink)
                
            } catch let error as DynamicLinksSDKError {
                print("Error handling link: \(error.localizedDescription)")
            }
        }
    }
}
```

### 3. Handle Deferred Deep Links

When someone taps your link before the app is installed, the SDK can hand you
that link on the first launch after install. Pass `onDeferredDeeplink` to
`initialize`: the SDK checks once, on first launch, and calls you back on the
main thread.

```swift
DynamicLinksSDK.initialize(
    baseUrl: "https://api.grivn.com",
    secretKey: "your_secret_key",
    projectId: "your_project_id"
) { result in
    guard result.found, let url = result.originalUrl else { return }
    // Route to the content the user tapped, e.g. handleDeepLink(URL(string: url))
    print("Deferred deep link: \(url), utm_source: \(result.utmSource ?? "none")")
}
```

`initialize` always runs this check on first launch, with or without a
callback, so the callback is how you receive the result. Calling
`checkDeferredDeeplink()` yourself afterwards returns `found == false`, because
the first launch has already been checked. To repeat the lookup while testing,
force it:

```swift
// Testing only: repeat the lookup on a later launch
let result = try await DynamicLinksSDK.shared.checkDeferredDeeplink(forceCheck: true)
```

With analytics turned off (`DynamicLinksSDK.setAnalyticsEnabled(false)`), the
SDK makes no deferred lookup and `found` is always `false`.

### 4. Handle Pasteboard Dynamic Links

On iOS 16+, reading pasteboard content triggers a system permission banner.
Use `hasPossibleDynamicLink()` (no prompt) to check first, then read only on user action.

#### Step 1: Check (no prompt)
```swift
if DynamicLinksSDK.shared.hasPossibleDynamicLink() {
    // Show a banner or button inviting the user to paste
}
```

#### Step 2: Read on user action
```swift
// Called when user taps "Open copied link" button
do {
    let dynamicLink = try await DynamicLinksSDK.shared.handlePasteboardDynamicLink()
    handleDeepLink(dynamicLink.url)
} catch DynamicLinksSDKError.noURLInPasteboard {
    // No dynamic link in pasteboard
} catch DynamicLinksSDKError.alreadyCheckedPasteboard {
    // Already checked once this session
} catch {
    print("Error: \(error)")
}
```

> **Important**: Do NOT call `handlePasteboardDynamicLink()` automatically
> (e.g. in `sceneDidBecomeActive`). This triggers the system paste prompt every time.

### 5. Create (Shorten) Dynamic Links

Create a short dynamic link from components:

```swift
import DynamicLinks

Task {
    do {
        guard let components = DynamicLinkComponents(
            link: URL(string: "https://myapp.com/product/123")!,
            domainURIPrefix: "https://YOUR_PROJECT_ID.grivn.com",
            iOSParameters: DynamicLinkIOSParameters(
                appStoreID: "123456789",
                fallbackURL: URL(string: "https://apps.apple.com/app/id123456789")
            ),
            androidParameters: DynamicLinkAndroidParameters(
                packageName: "com.myapp.android",
                fallbackURL: URL(string: "https://play.google.com/store/apps/details?id=com.myapp.android"),
                minimumVersion: 10
            ),
            socialMetaTagParameters: DynamicLinkSocialMetaTagParameters(
                title: "Check out this product!",
                descriptionText: "Amazing product on sale",
                imageURL: URL(string: "https://myapp.com/product/123/image.jpg")
            ),
            analyticsParameters: DynamicLinkAnalyticsParameters(
                source: "email",
                medium: "newsletter",
                campaign: "summer_sale"
            )
        ) else {
            print("Failed to create components")
            return
        }
        
        let response = try await DynamicLinksSDK.shared.shorten(dynamicLink: components)
        
        // Get the short link
        let shortLink = response.shortLink
        print("Short link: \(shortLink?.absoluteString ?? "")")
        
    } catch let error as DynamicLinksSDKError {
        print("Error creating link: \(error.localizedDescription)")
    }
}
```

## Privacy & App Review

### How iOS deferred deep links are matched

When someone opens a Grivn link before installing your app, Grivn records the
click. On first launch the SDK asks Grivn for a recent matching click, by the
device type (phone or tablet) and OS plus either the exact request IP address
within 48 hours, or the same /24 range and the device language within 2 hours.
Without a network match there is no match. The SDK itself computes no device
identifier.

This is probabilistic. On a shared network (an office, a campus) it can pick up
a click made on another device, so treat a match as a hint: don't grant
referral rewards or link accounts on a match alone.

### Apple's rules

Apple's Developer Program License Agreement (§3.3.3) and its
[User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
page prohibit deriving data from a device to uniquely identify it
("fingerprinting"), and App Tracking Transparency permission does not make it
allowed. App Review has rejected apps for SDKs that match users with
probabilistic methods. Grivn uses coarse signals and short-lived records, but
whether that is acceptable for your app is your call.

If you'd rather not use probabilistic matching, turn it off before
initializing the SDK:

```swift
DynamicLinksSDK.setAnalyticsEnabled(false)
DynamicLinksSDK.initialize(baseUrl: "https://api.grivn.com", secretKey: "YOUR_GRIVN_API_KEY", projectId: "YOUR_PROJECT_ID")
```

With analytics off, the SDK makes no deferred lookup, sends no install
confirmation and no events. Universal Links still open your app, and the
pasteboard flow (step 3 above) still works; it needs a user tap and shows the
iOS paste prompt, but involves no matching.

### What the SDK sends

| When | Data |
|---|---|
| First launch (deferred lookup) | A User-Agent built from the device model, iOS version, app name and version; the device language. Grivn also sees the request IP. |
| After a match (install confirmation) | Device model, iOS version, app version |
| Events (batched) | `identifierForVendor`, iOS version, app version, SDK version; per event the name, parameters (for deep link opens, the link URL), time, and the user ID if you call `setUserId` |
| Never | IDFA, App Tracking Transparency, keychain, contacts, location |

Retention is described in Grivn's [privacy policy](https://www.grivn.com/privacy).

### Privacy manifest

The package ships a `PrivacyInfo.xcprivacy`, which Xcode merges into your
app's privacy report. It declares no tracking; Device ID, Product Interaction,
and User ID (only when you call `setUserId`) collected for analytics; and
UserDefaults access with reason `CA92.1`.

### App Store privacy labels

A starting point. You are responsible for your app's labels.

| If your app… | Declare | Purpose | Linked to user | Tracking |
|---|---|---|---|---|
| Uses the SDK with defaults | Identifiers → Device ID | Analytics, App Functionality | No | No |
| Uses the SDK with defaults | Usage Data → Product Interaction | Analytics | No | No |
| Calls `setUserId` | Identifiers → User ID; set the rows above to linked | Analytics | Yes | No |
| Uses Grivn campaign attribution to measure paid ads | The rows above, marked as used for tracking; request ATT permission first | Third-Party Advertising | Depends on your setup | Yes |
| Calls `setAnalyticsEnabled(false)` | Nothing from this SDK | — | — | — |

## API Reference

### DynamicLinksSDK

| Method | Description |
|--------|-------------|
| `initialize(baseUrl:secretKey:projectId:)` | Initialize the SDK with backend credentials |
| `initialize(baseUrl:secretKey:projectId:onDeferredDeeplink:)` | Initialize and get the deferred deep link (if any) on first launch |
| `checkDeferredDeeplink(forceCheck:)` | Repeat the deferred lookup (testing); `initialize` already checks on first launch |
| `configure(allowedHosts:)` | Set allowed hosts for link validation |
| `setTrustAllCerts(_:)` | Trust all SSL certificates (dev only) |
| `handleDynamicLink(_:)` | Parse a dynamic link and return `DynamicLink` |
| `hasPossibleDynamicLink()` | Check if pasteboard may contain a dynamic link (no iOS 16+ prompt) |
| `handlePasteboardDynamicLink()` | Read and resolve pasteboard dynamic link (triggers iOS 16+ prompt) |
| `shorten(dynamicLink:projectId:)` | Create a short link from `DynamicLinkComponents` |
| `isValidDynamicLink(url:)` | Check if a URL is a valid dynamic link |

### DynamicLinkComponents

Parameters for creating a dynamic link:

| Parameter | Type | Description |
|-----------|------|-------------|
| `link` | `URL` | Target deep link URL |
| `domainURIPrefix` | `String` | Short link domain prefix |
| `iOSParameters` | `DynamicLinkIOSParameters` | iOS-specific settings |
| `androidParameters` | `DynamicLinkAndroidParameters?` | Android-specific settings |
| `analyticsParameters` | `DynamicLinkAnalyticsParameters?` | UTM tracking parameters |
| `socialMetaTagParameters` | `DynamicLinkSocialMetaTagParameters?` | Social sharing preview |
| `iTunesConnectParameters` | `DynamicLinkItunesConnectAnalyticsParameters?` | iTunes affiliate tracking |
| `otherPlatformParameters` | `DynamicLinkOtherPlatformParameters?` | Desktop fallback URL |
| `options` | `DynamicLinkOptionsParameters?` | Path mode: `.short` (deduped) / `.unguessable` (unique, default). Omit for backend default. |

### DynamicLink

Parsed dynamic link result:

| Property | Type | Description |
|----------|------|-------------|
| `url` | `URL?` | The deep link URL |
| `utmParameters` | `[String: String]` | UTM tracking parameters |
| `minimumAppVersion` | `String?` | Minimum required app version (iOS) |

### Error Handling

```swift
do {
    let link = try await DynamicLinksSDK.shared.handleDynamicLink(url)
} catch let error as DynamicLinksSDKError {
    switch error {
    case .notInitialized:
        // SDK not initialized, call initialize() first
        break
    case .invalidDynamicLink:
        // Link is not a valid dynamic link
        break
    case .projectIdNotSet:
        // Project ID required for shortening
        break
    case .noURLInPasteboard:
        // No URL in pasteboard
        break
    case .alreadyCheckedPasteboard:
        // Already checked pasteboard once
        break
    case .networkError(let message, _):
        // Network request failed
        print("Network error: \(message)")
    case .serverError(let message, let code):
        // Server returned an error
        print("Server error (\(code)): \(message)")
    case .parseError(let message, _):
        // Failed to parse server response
        print("Parse error: \(message)")
    case .appUpdateRequired(let currentVersion, let requiredVersion, let appStoreId):
        // The link requires a newer app version — prompt the user to update.
        print("Update required: \(currentVersion) < \(requiredVersion), appStoreId=\(appStoreId ?? "n/a")")
    }
}
```

## Development Setup

For development/testing with self-signed certificates:

```swift
DynamicLinksSDK
    .setTrustAllCerts(true)  // ⚠️ Only for development!
    .initialize(
        baseUrl: "https://localhost:8080",
        secretKey: "dev_secret_key",
        projectId: "test_project"
    )
```

## Objective-C Support

The SDK is fully compatible with Objective-C:

```objc
#import <DynamicLinks/DynamicLinks-Swift.h>

// Initialize
[DynamicLinksSDK initializeWithBaseUrl:@"https://api.grivn.com"
                             secretKey:@"your_secret_key"
                             projectId:@"your_project_id"];

[DynamicLinksSDK configureWithAllowedHosts:@[@"YOUR_PROJECT_ID.grivn.com"]];

// Handle dynamic link
[[DynamicLinksSDK shared] handleDynamicLink:incomingURL 
                                 completion:^(DynamicLink *link, NSError *error) {
    if (error) {
        NSLog(@"Error: %@", error.localizedDescription);
        return;
    }
    NSURL *deepLink = link.url;
    // Handle deep link
}];
```

## License

MIT License - see [LICENSE](LICENSE) for details.
