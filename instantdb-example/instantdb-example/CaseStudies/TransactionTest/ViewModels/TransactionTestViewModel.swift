import Foundation
import InstantDB

@MainActor
class TransactionTestViewModel: ObservableObject {
  @Published var goals: [Goal] = []
  @Published var isLoading = false
  @Published var error: String?
  @Published var transactionLog: [String] = []
  @Published var showCreateSheet = false
  @Published var editingGoalId: String?

  private var unsubscribe: (() -> Void)?
  private weak var db: InstantClient?

  func setup(db: InstantClient) {
    self.db = db
    subscribeToGoals()
  }

  func cleanup() {
    unsubscribe?()
  }

  private func subscribeToGoals() {
    guard let db = db else { return }

    do {
      unsubscribe = try db.subscribe(
        db.query(Goal.self)
      ) { [weak self] result in
        guard let self else { return }
        self.isLoading = result.isLoading
        self.error = result.error?.localizedDescription
        self.goals = result.data

        if !result.isLoading && result.error == nil {
          self.log("[INFO] Received \(result.data.count) goals from query")
        }
      }
      log("[INFO] Subscribed to goals query")
    } catch {
      log("[ERROR] Failed to subscribe: \(error.localizedDescription)")
    }
  }

  func createGoal(title: String, difficulty: Int) {
    guard let db = db else { return }

    do {
      let goalId = newId()
      try db.transact(
        db.tx.goals[goalId].update([
          "title": title,
          "difficulty": difficulty
        ])
      )
      log("[SUCCESS] Created goal: \(title) (difficulty: \(difficulty))")
    } catch {
      log("[ERROR] Failed to create goal: \(error.localizedDescription)")
    }
  }

  func updateGoal(goalId: String, title: String, difficulty: Int) {
    guard let db = db else { return }

    do {
      try db.transact(
        db.tx.goals[goalId].update([
          "title": title,
          "difficulty": difficulty
        ])
      )
      log("[SUCCESS] Updated goal: \(title)")
      editingGoalId = nil
    } catch {
      log("[ERROR] Failed to update: \(error.localizedDescription)")
    }
  }

  func deleteGoal(goalId: String) {
    guard let db = db else { return }

    do {
      try db.transact(
        db.tx.goals[goalId].delete()
      )
      log("[SUCCESS] Deleted goal: \(goalId)")
      editingGoalId = nil
    } catch {
      log("[ERROR] Failed to delete: \(error.localizedDescription)")
    }
  }

  private func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    transactionLog.append("[\(timestamp)] \(message)")
  }
}
