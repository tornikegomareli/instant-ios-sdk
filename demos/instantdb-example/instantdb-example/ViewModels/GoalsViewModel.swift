import Foundation
import InstantDB
import Combine

/// Manages the Goals list with real-time subscriptions and local-first mutations.
///
/// This demonstrates:
/// - Real-time query subscription via `db.subscribe()`
/// - Local-first transactions via `db.transactLocalFirst()`
/// - Immediate UI updates before server confirmation
/// - Cross-device sync (changes appear on all connected clients)
@MainActor
final class GoalsViewModel: ObservableObject {
  @Published var goals: [Goal] = []
  @Published var isLoading = true
  @Published var error: String?

  private var subscriptions = Set<SubscriptionToken>()
  private weak var db: InstantClient?

  func setup(db: InstantClient) {
    guard self.db == nil else { return }
    self.db = db
    subscribeToGoals()
  }

  // MARK: - Subscription

  private func subscribeToGoals() {
    guard let db else { return }

    do {
      try db.subscribe(db.query(Goal.self)) { [weak self] result in
        guard let self else { return }
        self.isLoading = result.isLoading
        self.error = result.error?.localizedDescription
        if !result.isLoading {
          self.goals = result.data
        }
      }
      .store(in: &subscriptions)
    } catch {
      self.error = error.localizedDescription
    }
  }

  // MARK: - Mutations

  func createGoal(title: String, difficulty: Int) {
    guard let db else { return }

    Task {
      do {
        try await db.transactLocalFirst {
          Goal.create(title: title, difficulty: difficulty, completed: false)
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func updateGoal(id: String, title: String, difficulty: Int) {
    guard let db else { return }

    Task {
      do {
        try await db.transactLocalFirst {
          Goal.update(id: id, title: title, difficulty: difficulty)
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func toggleCompleted(goal: Goal) {
    guard let db else { return }

    let newValue = !(goal.completed ?? false)
    Task {
      do {
        try await db.transactLocalFirst {
          Goal.update(id: goal.id, completed: newValue)
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func deleteGoal(id: String) {
    guard let db else { return }

    Task {
      do {
        try await db.transactLocalFirst {
          Goal.delete(id: id)
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func createSampleGoals() {
    guard let db else { return }

    let samples: [(String, Int)] = [
      ("Learn SwiftUI", 3),
      ("Ship iOS app", 7),
      ("Write tests", 4),
      ("Read SICP", 8),
      ("Run a marathon", 9),
    ]

    Task {
      do {
        try await db.transactLocalFirst {
          for (title, difficulty) in samples {
            Goal.create(title: title, difficulty: difficulty, completed: false)
          }
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func deleteAllGoals() {
    guard let db else { return }

    let ids = goals.map(\.id)
    guard !ids.isEmpty else { return }

    Task {
      do {
        try await db.transactLocalFirst {
          for id in ids {
            Goal.delete(id: id)
          }
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
