import Foundation

// MARK: - QueryOnceError

/// Errors produced by `InstantClient.queryOnce`.
///
/// ## Why This Exists
/// InstantDB's `queryOnce` is intentionally stricter than subscriptions:
/// - Subscriptions may return cached results immediately for offline-friendly UX.
/// - `queryOnce` fails when offline so callers cannot accidentally treat stale data
///   as a successful "fresh" read.
///
/// ## Last-Known Data
/// Some failure cases include `lastKnownResult` (if available) so callers can:
/// - show cached data with a clear offline/error UI, and
/// - retry when connectivity returns.
public enum QueryOnceError: Error, Sendable, LocalizedError {
  case offline(queryHash: String, lastKnownResult: Data?)
  case timedOut(queryHash: String, seconds: TimeInterval, lastKnownResult: Data?)
  case requestFailed(queryHash: String, message: String, lastKnownResult: Data?)

  public var errorDescription: String? {
    switch self {
    case let .offline(queryHash, _):
      return """
        ════════════════════════════════════════════════════════════════
        QUERY ONCE FAILED - Device Offline
        ════════════════════════════════════════════════════════════════

        WHAT HAPPENED:
          InstantDB could not run `queryOnce` because the client is offline.

        WHY THIS EXISTS:
          `queryOnce` is intentionally strict to avoid returning stale cached
          data as a success result. For offline-friendly reads, use subscriptions
          which may emit cached results immediately and refresh once online.

        DETAILS:
          queryHash: \(queryHash)

        HOW TO FIX:
          1. Retry when the device is online, OR
          2. Use `subscribe` / `TypedQuery.values()` for cached-first UX.
        ════════════════════════════════════════════════════════════════
        """

    case let .timedOut(queryHash, seconds, _):
      return """
        ════════════════════════════════════════════════════════════════
        QUERY ONCE FAILED - Timed Out
        ════════════════════════════════════════════════════════════════

        WHAT HAPPENED:
          InstantDB did not receive a server response within \(seconds)s.

        WHY THIS HAPPENS:
          Network latency, connection instability, or the server being unreachable.

        DETAILS:
          queryHash: \(queryHash)

        HOW TO FIX:
          1. Check network connectivity and retry, OR
          2. Use a subscription for long-lived reads.
        ════════════════════════════════════════════════════════════════
        """

    case let .requestFailed(queryHash, message, _):
      return """
        ════════════════════════════════════════════════════════════════
        QUERY ONCE FAILED - Request Error
        ════════════════════════════════════════════════════════════════

        WHAT HAPPENED:
          InstantDB failed to send the query or process the server response.

        DETAILS:
          queryHash: \(queryHash)
          error: \(message)

        HOW TO FIX:
          1. Retry, OR
          2. Switch to a subscription for resiliency.
        ════════════════════════════════════════════════════════════════
        """
    }
  }

  /// The last-known cached result payload, if available.
  public var lastKnownResult: Data? {
    switch self {
    case let .offline(_, data):
      return data
    case let .timedOut(_, _, data):
      return data
    case let .requestFailed(_, _, data):
      return data
    }
  }

  /// Decodes the last-known cached entities for a namespace.
  ///
  /// This is a convenience for callers who want to show cached data in an
  /// error UI, while still treating the overall operation as a failure.
  ///
  /// - Parameters:
  ///   - type: The entity type to decode.
  ///   - namespace: The top-level query namespace.
  /// - Returns: Decoded entities if a cached payload exists and decoding succeeds.
  public func decodeLastKnownEntities<T: Decodable>(_ type: T.Type, from namespace: String) -> [T]? {
    guard let queryResult = lastKnownQueryResult else { return nil }
    return queryResult.decode(type, from: namespace)
  }

  /// The last-known cached result as a `QueryResult`, if available.
  public var lastKnownQueryResult: QueryResult? {
    guard let data = lastKnownResult else { return nil }

    do {
      guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
      guard let cachedData = obj["data"] as? [String: Any] else { return nil }

      let pageInfo: [String: Any]?
      if obj["pageInfo"] is NSNull {
        pageInfo = nil
      } else {
        pageInfo = obj["pageInfo"] as? [String: Any]
      }

      return QueryResult.success(data: cachedData, pageInfo: pageInfo)
    } catch {
      return nil
    }
  }
}

