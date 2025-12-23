import Foundation

// MARK: - InstantLog

/// Lightweight, stdout-focused logging for the Swift SDK.
///
/// ## Why This Exists
/// The SDK historically used many `print` statements for debugging transport and query
/// behavior. That was useful during development, but it becomes noisy in real apps and
/// in test output (especially for `refresh-ok` and large query payloads).
///
/// This helper lets us keep the debugging hooks while making them opt-in.
///
/// ## Configuration
/// - `INSTANTDB_LOG_LEVEL`: `off`, `error`, `info`, `debug` (default: `error`)
/// - `INSTANTDB_DEBUG=1`: forces `debug`
enum InstantLog {
  enum Level: Int {
    case off = 0
    case error = 1
    case info = 2
    case debug = 3
  }

  private static let onceLock = NSLock()
  private static var onceTokens = Set<String>()

  static var level: Level = {
    let env = ProcessInfo.processInfo.environment

    if env["INSTANTDB_DEBUG"] == "1" {
      return .debug
    }

    if let rawLevel = env["INSTANTDB_LOG_LEVEL"]?.lowercased() {
      switch rawLevel {
      case "off", "none", "0":
        return .off
      case "error":
        return .error
      case "info":
        return .info
      case "debug":
        return .debug
      default:
        break
      }
    }

    return .error
  }()

  static func debugOnce(_ token: String, _ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.debug.rawValue else { return }
    guard shouldEmitOnce(token) else { return }
    print(message())
  }

  static func debug(_ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.debug.rawValue else { return }
    print(message())
  }

  static func info(_ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.info.rawValue else { return }
    print(message())
  }

  static func warning(_ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.error.rawValue else { return }
    print(message())
  }

  static func warningOnce(_ token: String, _ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.error.rawValue else { return }
    guard shouldEmitOnce(token) else { return }
    print(message())
  }

  static func error(_ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.error.rawValue else { return }
    print(message())
  }

  static func errorOnce(_ token: String, _ message: @autoclosure () -> String) {
    guard level.rawValue >= Level.error.rawValue else { return }
    guard shouldEmitOnce(token) else { return }
    print(message())
  }

  private static func shouldEmitOnce(_ token: String) -> Bool {
    onceLock.lock()
    defer { onceLock.unlock() }
    return onceTokens.insert(token).inserted
  }
}
