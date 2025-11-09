# Authentication Guide

> Complete guide to authentication in InstantDB iOS SDK

## Overview

InstantDB iOS SDK provides comprehensive authentication support with multiple sign-in methods. All authentication is handled through the `AuthManager` class.

**Official InstantDB Auth Documentation**: [https://instantdb.com/docs/auth](https://instantdb.com/docs/auth)

## Quick Start

```swift
import InstantDB

let db = InstantClient(appID: "your-app-id")
let authManager = db.authManager

// Sign in with Magic Code
try await authManager.sendMagicCode(email: "user@example.com")
try await authManager.signInWithMagicCode(email: "user@example.com", code: "123456")

// Or sign in as guest
try await authManager.signInAsGuest()

// Check auth state
if authManager.state.isAuthenticated {
  print("Logged in as: \(authManager.currentUser?.email ?? "guest")")
}
```

## Supported Authentication Methods

| Method | Status | Setup Required |
|--------|--------|----------------|
| [Magic Code](#magic-code-authentication) | ✅ | None |
| [Guest Authentication](#guest-authentication) | ✅ | None |
| [Sign in with Apple](#sign-in-with-apple) | ✅ | Apple Developer Account |
| [Sign in with Google](#sign-in-with-google) | ✅ | Google Cloud Project |
| [GitHub OAuth](#github-oauth) | ✅ | GitHub OAuth App |
| [LinkedIn OAuth](#linkedin-oauth) | ✅ | LinkedIn OAuth App |
| [Clerk](#clerk-integration) | ✅ | Clerk Account |

---

## Magic Code Authentication

Passwordless email authentication using one-time codes.

**Official Docs**: [InstantDB Magic Code](https://instantdb.com/docs/auth#magic-code)

### Implementation

```swift
// Step 1: Send magic code to email
try await authManager.sendMagicCode(email: "user@example.com")

// Step 2: User receives code via email, then verify
try await authManager.signInWithMagicCode(
  email: "user@example.com",
  code: "123456"
)
```

### Setup

No additional setup required! Works out of the box.

### Example App

See: `instantdb-example/AuthExamples/MagicCodeExample.swift`

---

## Guest Authentication

Anonymous authentication for users without credentials.

**Official Docs**: [InstantDB Guest Auth](https://instantdb.com/docs/auth#guest)

### Implementation

```swift
// Sign in as guest
try await authManager.signInAsGuest()

// Later, upgrade to full account
try await authManager.sendMagicCode(email: "user@example.com")
try await authManager.signInWithMagicCode(
  email: "user@example.com",
  code: "123456"
)
```

### Setup

No additional setup required!

### Example App

See: `instantdb-example/AuthExamples/GuestSignInExample.swift`

---

## Sign in with Apple

Native Apple authentication using AuthenticationServices framework.

**Official Docs**: [InstantDB OAuth](https://instantdb.com/docs/auth#oauth)

### Implementation

```swift
import AuthenticationServices
import InstantDB

let signInWithApple = SignInWithApple()

// Present Apple Sign-In
guard let window = UIApplication.shared.windows.first else { return }
let idToken = try await signInWithApple.signIn(presentationAnchor: window)

// Authenticate with InstantDB
try await authManager.signInWithIdToken(
  clientName: "apple-ios",
  idToken: idToken
)
```

### Setup

1. **Enable Sign in with Apple** in Xcode:
   - Go to: Target → Signing & Capabilities
   - Click "+ Capability"
   - Add "Sign in with Apple"

2. **Configure InstantDB Dashboard**:
   - Go to [InstantDB Dashboard](https://instantdb.com/dash)
   - Navigate to: Your App → Auth → OAuth Clients
   - Add new client:
     - **Name**: `apple-ios`
     - **Provider**: Apple
     - **Bundle ID**: Your app's bundle identifier

3. **Update Config**:
   ```swift
   // Config/Config.swift (already set up)
   static let instantAppID = "your-app-id"
   ```

### Example App

See: `instantdb-example/AuthExamples/AppleSignInExample.swift`

---

## Sign in with Google

Native Google authentication using Google Sign-In SDK.

**Official Docs**: [InstantDB OAuth](https://instantdb.com/docs/auth#oauth)
**Google Docs**: [Google Sign-In iOS](https://developers.google.com/identity/sign-in/ios)

### Implementation

```swift
import GoogleSignIn
import InstantDB

let googleSignIn = SignInWithGoogle(clientID: AppConfig.googleClientID)

// Present Google Sign-In
guard let rootViewController = window.rootViewController else { return }
let idToken = try await googleSignIn.signIn(
  presentingViewController: rootViewController
)

// Authenticate with InstantDB
try await authManager.signInWithIdToken(
  clientName: "google-ios",
  idToken: idToken
)
```

### Setup

1. **Create Google Cloud Project**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create new project or select existing
   - Enable "Google Sign-In API"

2. **Create OAuth 2.0 Credentials**:
   - Go to: APIs & Services → Credentials
   - Create OAuth 2.0 Client ID
   - Type: iOS
   - Bundle ID: Your app's bundle identifier
   - Copy the **Client ID**

3. **Configure InstantDB Dashboard**:
   - Go to [InstantDB Dashboard](https://instantdb.com/dash)
   - Navigate to: Your App → Auth → OAuth Clients
   - Add new client:
     - **Name**: `google-ios`
     - **Provider**: Google
     - **Client ID**: Your Google OAuth Client ID

4. **Add to Config**:
   ```swift
   // Config/Config.swift
   static let googleClientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
   ```

5. **Update Info.plist**:
   You need to add the URL scheme. Let me know and I'll tell you exactly what to add.

### Example App

See: `instantdb-example/AuthExamples/GoogleSignInExample.swift`

---

## GitHub OAuth

OAuth authentication via GitHub using web flow.

**Official Docs**: [InstantDB OAuth](https://instantdb.com/docs/auth#oauth)
**GitHub Docs**: [Creating an OAuth App](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app)

### Implementation

```swift
import InstantDB

let oauth = InstantOAuth(appID: db.appID)

// Start OAuth flow
guard let window = UIApplication.shared.windows.first else { return }
let code = try await oauth.startOAuth(
  provider: .github(clientName: "github-ios"),
  presentationAnchor: window
)

// Exchange code for token
try await authManager.signInWithOAuth(code: code)
```

### Setup

1. **Create GitHub OAuth App**:
   - Go to [GitHub Settings → Developer settings → OAuth Apps](https://github.com/settings/developers)
   - Click "New OAuth App"
   - Fill in:
     - **Application name**: Your app name
     - **Homepage URL**: `https://yourapp.com`
     - **Authorization callback URL**: `https://api.instantdb.com/runtime/oauth/callback`
   - Copy **Client ID** and **Client Secret**

2. **Configure InstantDB Dashboard**:
   - Go to [InstantDB Dashboard](https://instantdb.com/dash)
   - Navigate to: Your App → Auth → OAuth Clients
   - Add new client:
     - **Name**: `github-ios`
     - **Provider**: GitHub
     - **Client ID**: Your GitHub Client ID
     - **Client Secret**: Your GitHub Client Secret

### Example App

See: `instantdb-example/AuthExamples/GitHubSignInExample.swift`

---

## LinkedIn OAuth

OAuth authentication via LinkedIn using web flow.

**Official Docs**: [InstantDB OAuth](https://instantdb.com/docs/auth#oauth)
**LinkedIn Docs**: [OAuth 2.0](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authentication)

### Implementation

```swift
import InstantDB

let oauth = InstantOAuth(appID: db.appID)

// Start OAuth flow
guard let window = UIApplication.shared.windows.first else { return }
let code = try await oauth.startOAuth(
  provider: .linkedin(clientName: "linkedin-ios"),
  presentationAnchor: window
)

// Exchange code for token
try await authManager.signInWithOAuth(code: code)
```

### Setup

1. **Create LinkedIn App**:
   - Go to [LinkedIn Developers](https://www.linkedin.com/developers/apps)
   - Click "Create app"
   - Fill in required information
   - Under "Auth" tab:
     - Add redirect URL: `https://api.instantdb.com/runtime/oauth/callback`
   - Copy **Client ID** and **Client Secret**

2. **Configure InstantDB Dashboard**:
   - Go to [InstantDB Dashboard](https://instantdb.com/dash)
   - Navigate to: Your App → Auth → OAuth Clients
   - Add new client:
     - **Name**: `linkedin-ios`
     - **Provider**: LinkedIn
     - **Client ID**: Your LinkedIn Client ID
     - **Client Secret**: Your LinkedIn Client Secret

### Example App

See: `instantdb-example/AuthExamples/LinkedInSignInExample.swift`

---

## Clerk Integration

Third-party authentication platform integration.

**Official Docs**: [InstantDB Clerk](https://instantdb.com/docs/auth#clerk)
**Clerk Docs**: [Clerk iOS SDK](https://clerk.com/docs/quickstarts/ios)

### Implementation

```swift
import Clerk
import InstantDB

// Step 1: Configure Clerk in app init
init() {
  Clerk.shared.configure(publishableKey: AppConfig.clerkPublishableKey)
}

// Step 2: Load Clerk
.task {
  try? await Clerk.shared.load()
}

// Step 3: Show Clerk auth UI
.sheet(isPresented: $showAuth) {
  AuthView()
}

// Step 4: Link to InstantDB
guard let session = Clerk.shared.session else { return }
let token = try await session.getToken()

try await authManager.signInWithIdToken(
  clientName: "clerk",
  idToken: token!.jwt
)
```

### Setup

1. **Create Clerk Account**:
   - Go to [Clerk Dashboard](https://dashboard.clerk.com/)
   - Create new application
   - Copy **Publishable Key**

2. **Configure InstantDB Dashboard**:
   - Go to [InstantDB Dashboard](https://instantdb.com/dash)
   - Navigate to: Your App → Auth → OAuth Clients
   - Add new client:
     - **Name**: `clerk`
     - **Provider**: Clerk
     - **Client ID**: Your Clerk Frontend API URL

3. **Add to Config**:
   ```swift
   // Config/Config.swift
   static let clerkPublishableKey = "pk_test_..."
   ```

4. **Add Clerk SDK**:
   Already included in example app via SPM.

### Example App

See: `instantdb-example/AuthExamples/ClerkSignInExample.swift`

---

## Auth State Management

The SDK provides comprehensive auth state tracking:

```swift
// Auth states
enum AuthState {
  case loading           // Checking for stored tokens
  case unauthenticated   // No user signed in
  case guest(User)       // Signed in as guest
  case authenticated(User) // Signed in with credentials
}

// Subscribe to auth changes
authManager.$state
  .sink { state in
    switch state {
    case .authenticated(let user):
      print("Logged in: \(user.email ?? "N/A")")
    case .guest:
      print("Guest user")
    case .unauthenticated:
      print("Not signed in")
    case .loading:
      print("Loading...")
    }
  }
  .store(in: &cancellables)

// Check current state
if authManager.state.isAuthenticated {
  // User is authenticated
}

if authManager.state.isGuest {
  // User is guest
}
```

## Sign Out

```swift
// Sign out current user
try await authManager.signOut()

// This will:
// 1. Invalidate token on server
// 2. Clear local keychain storage
// 3. Update auth state to .unauthenticated
```

## Token Management

Tokens are automatically managed:
- ✅ Stored securely in Keychain
- ✅ Restored on app launch
- ✅ Attached to all API requests
- ✅ Invalidated on sign out

## Configuration File Setup

All API keys should be stored in a configuration file:

```swift
// Config/Config.example.swift (template - committed to repo)
enum AppConfig {
  static let instantAppID = "YOUR_INSTANT_APP_ID_HERE"
  static let googleClientID = "YOUR_GOOGLE_CLIENT_ID_HERE"
  static let clerkPublishableKey = "YOUR_CLERK_PUBLISHABLE_KEY_HERE"
}
```

```swift
// Config/Config.swift (actual keys - gitignored)
enum AppConfig {
  static let instantAppID = "a8a567cc-..."
  static let googleClientID = "855344946109-..."
  static let clerkPublishableKey = "pk_test_..."
}
```

Copy `Config.example.swift` to `Config.swift` and add your actual keys.

## Resources

- **InstantDB Auth Docs**: [https://instantdb.com/docs/auth](https://instantdb.com/docs/auth)
- **InstantDB Dashboard**: [https://instantdb.com/dash](https://instantdb.com/dash)
- **Example App**: `/instantdb-example/AuthExamples/`
- **SDK Source**: `/Sources/InstantDB/Auth/`

## Support

Questions? Join our [Discord](https://discord.com/invite/VU53p7uQcE)
