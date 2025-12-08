import Foundation

/// Pagination metadata returned from cursor-based queries
///
/// Use `pageInfo` to implement infinite scroll or paginated lists:
///
/// ```swift
/// for await result in db.query(Goal.self).first(10).values() {
///   self.goals = result.data
///
///   if result.pageInfo?.hasNextPage == true {
///     self.showLoadMoreButton = true
///   }
/// }
///
/// // Load next page
/// func loadMore() {
///   guard let cursor = pageInfo?.endCursor else { return }
///
///   for await result in db.query(Goal.self).first(10).after(cursor).values() {
///     self.goals.append(contentsOf: result.data)
///     self.pageInfo = result.pageInfo
///   }
/// }
/// ```
public struct PageInfo: Sendable {
  /// Cursor pointing to first item in current page
  public let startCursor: Cursor?

  /// Cursor pointing to last item in current page
  public let endCursor: Cursor?

  /// True if more results exist after current page
  public let hasNextPage: Bool

  /// True if more results exist before current page
  public let hasPreviousPage: Bool

  /// Parse PageInfo from server response dictionary
  ///
  /// Server format:
  /// ```json
  /// {
  ///   "goals": {
  ///     "start-cursor": [entityId, attrId, value, timestamp],
  ///     "end-cursor": [entityId, attrId, value, timestamp],
  ///     "has-next-page?": true,
  ///     "has-previous-page?": false
  ///   }
  /// }
  /// ```
  init?(from dict: [String: Any]?, namespace: String) {
    guard let dict = dict,
          let namespaceInfo = dict[namespace] as? [String: Any] else {
      return nil
    }

    if let startCursorArray = namespaceInfo["start-cursor"] as? [Any] {
      self.startCursor = Cursor(from: startCursorArray)
    } else {
      self.startCursor = nil
    }

    if let endCursorArray = namespaceInfo["end-cursor"] as? [Any] {
      self.endCursor = Cursor(from: endCursorArray)
    } else {
      self.endCursor = nil
    }

    self.hasNextPage = namespaceInfo["has-next-page?"] as? Bool ?? false
    self.hasPreviousPage = namespaceInfo["has-previous-page?"] as? Bool ?? false
  }

  init(
    startCursor: Cursor?,
    endCursor: Cursor?,
    hasNextPage: Bool,
    hasPreviousPage: Bool
  ) {
    self.startCursor = startCursor
    self.endCursor = endCursor
    self.hasNextPage = hasNextPage
    self.hasPreviousPage = hasPreviousPage
  }
}
