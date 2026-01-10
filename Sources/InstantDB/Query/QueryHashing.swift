import CryptoKit
import Foundation

// MARK: - QueryHashing

/// Utilities for producing a deterministic query identifier.
///
/// ## Why This Exists
/// InstantDB clients need a stable way to deduplicate identical queries and to
/// persist query caches across launches for offline mode.
///
/// Swift's `Hashable` / `hashValue` is intentionally randomized per-process and
/// **must not** be used for persisted identifiers. Using it would cause:
/// - Cache misses after app relaunch (same query → different hash).
/// - `refresh-ok` mismatches in edge cases where the canonical form differs.
///
/// This helper produces a canonical JSON representation (sorted keys) and then
/// hashes it using SHA-256 to create a deterministic identifier.
enum QueryHashing {
  static func hash(_ query: [String: Any]) -> String {
    let canonical = canonicalize(query)

    guard let data = try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys]) else {
      return UUID().uuidString.lowercased()
    }

    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  static func canonicalJSONData(_ query: [String: Any]) -> Data? {
    let canonical = canonicalize(query)
    return try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
  }

  private static func canonicalize(_ value: Any) -> Any {
    if let dict = value as? [String: Any] {
      var result: [String: Any] = [:]
      for key in dict.keys.sorted() {
        result[key] = canonicalize(dict[key] as Any)
      }
      return result
    }

    if let array = value as? [Any] {
      return array.map { canonicalize($0) }
    }

    return value
  }
}

