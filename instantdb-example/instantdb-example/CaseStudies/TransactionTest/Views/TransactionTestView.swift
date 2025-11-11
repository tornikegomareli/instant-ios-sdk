import SwiftUI
import InstantDB

struct TransactionTestView: View {
  @EnvironmentObject var db: InstantClient
  @StateObject private var viewModel = TransactionTestViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ConnectionStatusView(connectionState: db.connectionState)
        GoalsListView(viewModel: viewModel)
        LogView(title: "Local Logs", logs: $viewModel.transactionLog)
      }
      .padding()
    }
    .navigationTitle("Simple Transaction, Query Test")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { viewModel.showCreateSheet = true }) {
          Image(systemName: "plus")
        }
        .disabled(db.connectionState != .authenticated)
      }
    }
    .sheet(isPresented: $viewModel.showCreateSheet) {
      CreateGoalSheet(onSave: viewModel.createGoal)
    }
    .sheet(item: Binding(
      get: { viewModel.editingGoalId.map { GoalEditIdentifier(id: $0) } },
      set: { viewModel.editingGoalId = $0?.id }
    )) { identifier in
      if let goal = viewModel.goals.first(where: { $0["id"] as? String == identifier.id }) {
        EditGoalSheet(
          goal: goal,
          onSave: { title, difficulty in
            viewModel.updateGoal(goalId: identifier.id, title: title, difficulty: difficulty)
          },
          onDelete: {
            viewModel.deleteGoal(goalId: identifier.id)
          }
        )
      }
    }
    .onAppear {
      viewModel.setup(db: db)
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}

struct ConnectionStatusView: View {
  let connectionState: ConnectionState

  var body: some View {
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
    switch connectionState {
    case .authenticated: return .green
    case .connected: return .orange
    case .connecting: return .yellow
    case .disconnected, .error: return .red
    }
  }

  private var statusText: String {
    switch connectionState {
    case .authenticated: return "Authenticated"
    case .connected: return "Connected"
    case .connecting: return "Connecting..."
    case .disconnected: return "Disconnected"
    case .error(let err): return "Error: \(err.localizedDescription)"
    }
  }
}

struct GoalsListView: View {
  @ObservedObject var viewModel: TransactionTestViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Goals (\(viewModel.goals.count))")
        .font(.headline)

      if viewModel.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      } else if let error = viewModel.error {
        Text("Error: \(error)")
          .foregroundColor(.red)
          .font(.caption)
      } else if viewModel.goals.isEmpty {
        EmptyGoalsView()
      } else {
        ForEach(viewModel.goals.indices, id: \.self) { index in
          GoalCard(
            goal: viewModel.goals[index],
            onTap: {
              viewModel.editingGoalId = viewModel.goals[index]["id"] as? String
            },
            onDelete: {
              if let goalId = viewModel.goals[index]["id"] as? String {
                viewModel.deleteGoal(goalId: goalId)
              }
            }
          )
        }
      }
    }
    .padding()
    .background(Color.blue.opacity(0.05))
    .cornerRadius(12)
  }
}

struct EmptyGoalsView: View {
  var body: some View {
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
  }
}

struct GoalEditIdentifier: Identifiable {
  let id: String
}

#Preview {
  NavigationView {
    TransactionTestView()
      .environmentObject(InstantClient(appID: AppConfig.instantAppID))
  }
}
