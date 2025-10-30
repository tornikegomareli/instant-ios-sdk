import Foundation

/// Example configuration file
/// Copy this file to Config.swift and add your actual API keys
/// Config.swift is gitignored and will not be committed
enum AppConfig {

  /// Your InstantDB App ID
  /// Get it from: https://instantdb.com/dash
  static let instantAppID = "YOUR_INSTANT_APP_ID_HERE"

  /// Google Sign-In Client ID
  /// Get it from: https://console.cloud.google.com/
  /// Format: xxxxx.apps.googleusercontent.com
  static let googleClientID = "YOUR_GOOGLE_CLIENT_ID_HERE"

  /// Clerk Publishable Key
  /// Get it from: https://dashboard.clerk.com/
  /// Format: pk_test_xxxxx or pk_live_xxxxx
  static let clerkPublishableKey = "YOUR_CLERK_PUBLISHABLE_KEY_HERE"
}
