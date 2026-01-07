import Foundation
import os.log

// MARK: - CompatibilityLogger

/// A logging wrapper that provides cross-platform compatibility.
///
/// ## Why This Exists
///
/// The `Logger` type from `os.log` is only available in macOS 11.0+, iOS 14.0+,
/// tvOS 14.0+, and watchOS 7.0+. However, this SDK targets macOS 10.15, iOS 15,
/// tvOS 15, and watchOS 8, which means we need a fallback for macOS 10.15.
///
/// This wrapper uses `Logger` when available and falls back to `os_log` on
/// older platforms.
///
/// - Note: The string interpolation features of `Logger` (like privacy settings)
///   are not available in the fallback path, but basic logging works.
struct CompatibilityLogger {
  let subsystem: String
  let category: String
  
  private let osLog: OSLog
  
  init(subsystem: String, category: String) {
    self.subsystem = subsystem
    self.category = category
    self.osLog = OSLog(subsystem: subsystem, category: category)
  }
  
  // MARK: - Logging Methods
  
  /// Logs a debug message.
  func debug(_ message: String) {
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      let logger = Logger(subsystem: subsystem, category: category)
      logger.debug("\(message, privacy: .public)")
    } else {
      os_log(.debug, log: osLog, "%{public}@", message)
    }
  }
  
  /// Logs an info message.
  func info(_ message: String) {
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      let logger = Logger(subsystem: subsystem, category: category)
      logger.info("\(message, privacy: .public)")
    } else {
      os_log(.info, log: osLog, "%{public}@", message)
    }
  }
  
  /// Logs a warning message.
  func warning(_ message: String) {
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      let logger = Logger(subsystem: subsystem, category: category)
      logger.warning("\(message, privacy: .public)")
    } else {
      os_log(.default, log: osLog, "⚠️ %{public}@", message)
    }
  }
  
  /// Logs an error message.
  func error(_ message: String) {
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      let logger = Logger(subsystem: subsystem, category: category)
      logger.error("\(message, privacy: .public)")
    } else {
      os_log(.error, log: osLog, "%{public}@", message)
    }
  }
}




