//
//  Config.swift
//  instantdb-example
//
//  Created by Tornike Gomareli on 17.11.25.
//

import Foundation

/// Example configuration file
/// Copy this file to Config.swift and add your actual API keys
/// Config.swift is gitignored and will not be committed
enum AppConfig {
  /// Your InstantDB App ID
  /// Get it from: https://instantdb.com/dash
  static let instantAppID = "a8a567cc-34a7-41b4-8802-d81186ad7014"

  /// Google Sign-In Client ID
  /// Get it from: https://console.cloud.google.com/
  /// Format: xxxxx.apps.googleusercontent.com
  static let googleClientID = "855344946109-q2lc0rf5f9nttpqvhf9jon0sg5d7h44h.apps.googleusercontent.com"

  /// Clerk Publishable Key
  /// Get it from: https://dashboard.clerk.com/
  /// Format: pk_test_xxxxx or pk_live_xxxxx
  static let clerkPublishableKey = "pk_test_cHJpbWFyeS1jaGltcC02My5jbGVyay5hY2NvdW50cy5kZXYk"
}
