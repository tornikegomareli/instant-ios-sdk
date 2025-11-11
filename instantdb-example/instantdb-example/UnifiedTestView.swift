import SwiftUI
import InstantDB

struct UnifiedTestView: View {
  @EnvironmentObject var db: InstantClient
  @State private var goals: [[String: Any]] = []
  @State private var isLoading = false
  @State private var error: String?
  @State private var unsubscribe: (() -> Void)?
  @State private var transactionLog: [String] = []
  @State private var showCreateSheet = false
  @State private var editingGoalId: String?
  @State private var editingTitle: String = ""
  @State private var editingDifficulty: String = "5"

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        statusSection
        queryResultsSection
        LogView(title: "Local Logs", logs: $transactionLog)
      }
      .padding()
    }
    .navigationTitle("Simple Transaction, Query Test")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { showCreateSheet = true }) {
          Image(systemName: "plus")
        }
        .disabled(db.connectionState != .authenticated)
      }
    }
    .sheet(isPresented: $showCreateSheet) {
      CreateGoalSheet(onSave: createGoal)
    }
    .sheet(item: Binding(
      get: { editingGoalId.map { GoalEditIdentifier(id: $0) } },
      set: { editingGoalId = $0?.id }
    )) { identifier in
      if let goal = goals.first(where: { $0["id"] as? String == identifier.id }) {
        EditGoalSheet(
          goal: goal,
          onSave: { title, difficulty in
            updateGoal(goalId: identifier.id, title: title, difficulty: difficulty)
          },
          onDelete: {
            deleteGoal(goalId: identifier.id)
          }
        )
      }
    }
    .onAppear {
      subscribeToGoals()
    }
    .onDisappear {
      unsubscribe?()
    }
  }

  // MARK: - Status Section

  private var statusSection: some View {
    HStack {
      Circle()
        .fill(statusColor)
        .frame(width: 10, height: 10)
      Text("Status: \(statusText)")
        .font(.subheadline)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(8)
  }

  private var statusColor: Color {
    switch db.connectionState {
    case .authenticated: return .green
    case .connected: return .orange
    case .connecting: return .yellow
    case .disconnected, .error: return .red
    }
  }

  private var statusText: String {
    switch db.connectionState {
    case .authenticated: return "Authenticated"
    case .connected: return "Connected"
    case .connecting: return "Connecting..."
    case .disconnected: return "Disconnected"
    case .error(let err): return "Error: \(err.localizedDescription)"
    }
  }

  // MARK: - Query Results Section

  private var queryResultsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Goals (\(goals.count))")
        .font(.headline)

      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      } else if let error = error {
        Text("Error: \(error)")
          .foregroundColor(.red)
          .font(.caption)
      } else if goals.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "tray")
            .font(.largeTitle)
            .foregroundColor(.gray)
          Text("No goals yet")
            .font(.caption)
            .foregroundColor(.secondary)
          Text("Tap + to create your first goal")
            .font(.caption2)
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        ForEach(goals.indices, id: \.self) { index in
          goalCard(goals[index])
        }
      }
    }
    .padding()
    .background(Color.blue.opacity(0.05))
    .cornerRadius(12)
  }

  private func goalCard(_ goal: [String: Any]) -> some View {
    Button(action: {
      editingGoalId = goal["id"] as? String
    }) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(goal["title"] as? String ?? "Untitled")
            .font(.headline)
            .foregroundColor(.primary)
          Spacer()
          if let difficulty = goal["difficulty"] as? Int {
            DifficultyIndicator(level: difficulty)
          }
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Text("ID: \(goal["id"] as? String ?? "unknown")")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding()
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .cornerRadius(8)
      .shadow(color: Color.black.opacity(0.1), radius: 2)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        if let goalId = goal["id"] as? String {
          deleteGoal(goalId: goalId)
        }
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  // MARK: - Query Subscription

  private func subscribeToGoals() {
    do {
      unsubscribe = try db.subscribeQuery(["goals": [:]]) { result in
        DispatchQueue.main.async {
          self.isLoading = result.isLoading
          self.error = result.error?.localizedDescription

          if let goalsData = result["goals"] as? [[String: Any]] {
            self.goals = goalsData
            if !result.isLoading && result.error == nil {
              self.log("[INFO] Received \(goalsData.count) goals from query")
            }
          } else {
            self.goals = []
          }
        }
      }
      log("[INFO] Subscribed to goals query")
    } catch {
      log("[ERROR] Failed to subscribe: \(error.localizedDescription)")
    }
  }

  // MARK: - Transaction Actions

  private func createGoal(title: String, difficulty: Int) {
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

  private func updateGoal(goalId: String, title: String, difficulty: Int) {
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

  private func deleteGoal(goalId: String) {
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

  // MARK: - Helpers

  private func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    transactionLog.append("[\(timestamp)] \(message)")
  }
}

struct DifficultyIndicator: View {
  let level: Int

  private var color: Color {
    switch level {
    case 1...3: return .green
    case 4...6: return .orange
    case 7...10: return .red
    default: return .gray
    }
  }

  var body: some View {
    HStack(spacing: 3) {
      ForEach(1...10, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2)
          .fill(index <= level ? color : Color.gray.opacity(0.2))
          .frame(width: 3, height: 12)
      }
    }
  }
}

struct GoalEditIdentifier: Identifiable {
  let id: String
}

struct CreateGoalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title: String = ""
  @State private var difficultyText: String = "5"

  let onSave: (String, Int) -> Void

  var body: some View {
    NavigationView {
      Form {
        Section("Goal Details") {
          TextField("Title", text: $title)

          HStack {
            Text("Difficulty")
            TextField("1-10", text: $difficultyText)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
          }
        }
      }
      .navigationTitle("New Goal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            let difficulty = Int(difficultyText) ?? 5
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.isEmpty)
        }
      }
    }
  }
}

struct EditGoalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var difficultyText: String

  let onSave: (String, Int) -> Void
  let onDelete: () -> Void

  init(goal: [String: Any], onSave: @escaping (String, Int) -> Void, onDelete: @escaping () -> Void) {
    _title = State(initialValue: goal["title"] as? String ?? "")
    _difficultyText = State(initialValue: String(goal["difficulty"] as? Int ?? 5))
    self.onSave = onSave
    self.onDelete = onDelete
  }

  var body: some View {
    NavigationView {
      Form {
        Section("Goal Details") {
          TextField("Title", text: $title)

          HStack {
            Text("Difficulty")
            TextField("1-10", text: $difficultyText)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
          }
        }

        Section {
          Button(role: .destructive, action: {
            onDelete()
            dismiss()
          }) {
            HStack {
              Spacer()
              Text("Delete Goal")
              Spacer()
            }
          }
        }
      }
      .navigationTitle("Edit Goal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            let difficulty = Int(difficultyText) ?? 5
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.isEmpty)
        }
      }
    }
  }
}

#Preview {
  NavigationView {
    UnifiedTestView()
      .environmentObject(InstantClient(appID: AppConfig.instantAppID))
  }
}
