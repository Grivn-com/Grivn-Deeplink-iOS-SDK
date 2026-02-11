# DynamicLinks-iOS

iOS SDK for handling Dynamic Links with Grivn backend.

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/DynamicLinks-iOS.git", from: "1.0.0")
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
        DynamicLinksSDK.configure(allowedHosts: ["acme.wayp.link", "preview.acme.wayp.link"])
        
        return true
    }
}
```

### 2. Handle Dynamic Links

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

### 3. Handle Pasteboard Dynamic Links

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

### 4. Create (Shorten) Dynamic Links

Create a short dynamic link from components:

```swift
import DynamicLinks

Task {
    do {
        guard let components = DynamicLinkComponents(
            link: URL(string: "https://myapp.com/product/123")!,
            domainURIPrefix: "https://acme.wayp.link",
            iOSParameters: DynamicLinkIOSParameters(
                appStoreID: "123456789",
                fallbackURL: URL(string: "https://apps.apple.com/app/id123456789")
            ),
            androidParameters: DynamicLinkAndroidParameters(
                packageName: "com.myapp.android",
                fallbackURL: URL(string: "https://play.google.com/store/apps/details?id=com.myapp.android"),
                minimumVersion: 10
            ),
            analyticsParameters: DynamicLinkAnalyticsParameters(
                source: "email",
                medium: "newsletter",
                campaign: "summer_sale"
            ),
            socialMetaTagParameters: DynamicLinkSocialMetaTagParameters(
                title: "Check out this product!",
                descriptionText: "Amazing product on sale",
                imageURL: URL(string: "https://myapp.com/product/123/image.jpg")
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

## API Reference

### DynamicLinksSDK

| Method | Description |
|--------|-------------|
| `initialize(baseUrl:secretKey:projectId:)` | Initialize the SDK with backend credentials |
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

[DynamicLinksSDK configureWithAllowedHosts:@[@"acme.wayp.link"]];

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
