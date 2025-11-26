import Foundation
import ConcurrencyExtras

/// Token representing an active subscription that can be cancelled
///
/// Subscriptions automatically clean up when deallocated.
/// You can store multiple subscriptions in a Set for automatic lifecycle management:
///
/// ```swift
/// class GoalsViewModel {
///     private var subscriptions = Set<Subscription>()
///
///     func start() {
///         try? db.subscribe(db.query(Goal.self)) { result in
///             self.goals = result.data
///         }
///         .store(in: &subscriptions)
///     }
/// }
/// ```
public final class SubscriptionToken: Hashable, @unchecked Sendable {
  private let id = UUID()
  package var onCleanup: () -> Void
  private let isCancelled = LockIsolated(false)

  init(onCleanup: @escaping () -> Void) {
    self.onCleanup = onCleanup
  }

  /// Manually cancel the subscription
  public func cancel() {
    isCancelled.withValue { isCancelled in
      guard !isCancelled else { return }
      defer { isCancelled = true }
      onCleanup()
    }
  }
  
  /// Store subscription in a Set for automatic lifecycle management
  public func store(in set: inout Set<SubscriptionToken>) {
    set.insert(self)
  }
  
  deinit {
    cancel()
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
  
  public static func == (lhs: SubscriptionToken, rhs: SubscriptionToken) -> Bool {
    lhs.id == rhs.id
  }
}
