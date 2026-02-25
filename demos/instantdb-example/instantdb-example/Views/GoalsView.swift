import SwiftUI
import InstantDB

/// The main goals screen demonstrating real-time CRUD with cross-device sync.
///
/// Features shown:
/// - Live query subscription (goals update in real time across devices)
/// - Local-first mutations (create/update/delete appear instantly)
/// - Swipe to delete
/// - Tap to toggle completion
/// - Bulk operations (create samples, delete all)
struct GoalsView: View {
  @EnvironmentObject var db: InstantClient
  @StateObject private var viewModel = GoalsViewModel()
  @State private var showCreateSheet = false
  @State private var editingGoal: Goal?

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        goalsList
        ConnectionBanner()
      }
      .navigationTitle("Goals")
      #if !os(watchOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showCreateSheet = true
          } label: {
            Image(systemName: "plus")
          }
        }

        ToolbarItem(placement: .secondaryAction) {
          Menu {
            Button("Add Sample Goals", systemImage: "sparkles") {
              viewModel.createSampleGoals()
            }
            Button("Delete All", systemImage: "trash", role: .destructive) {
              viewModel.deleteAllGoals()
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      #endif
      .sheet(isPresented: $showCreateSheet) {
        CreateGoalSheet { title, difficulty in
          viewModel.createGoal(title: title, difficulty: difficulty)
        }
      }
      .sheet(item: $editingGoal) { goal in
        EditGoalSheet(
          goal: goal,
          onSave: { title, difficulty in
            viewModel.updateGoal(id: goal.id, title: title, difficulty: difficulty)
          },
          onDelete: {
            viewModel.deleteGoal(id: goal.id)
          }
        )
      }
      .onAppear {
        viewModel.setup(db: db)
      }
    }
  }

  @ViewBuilder
  private var goalsList: some View {
    if viewModel.isLoading {
      VStack {
        Spacer()
        ProgressView("Loading goals...")
        Spacer()
      }
    } else if let error = viewModel.error {
      VStack(spacing: 12) {
        Spacer()
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundStyle(.orange)
        Text(error)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Spacer()
      }
      .padding()
    } else if viewModel.goals.isEmpty {
      VStack(spacing: 12) {
        Spacer()
        Image(systemName: "target")
          .font(.system(size: 48))
          .foregroundStyle(.tertiary)
        Text("No goals yet")
          .font(.headline)
          .foregroundStyle(.secondary)
        Text("Tap + to create one, or add sample goals from the menu.")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
        #if os(watchOS)
        Button("Add Samples") {
          viewModel.createSampleGoals()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        #endif
        Spacer()
      }
      .padding()
    } else {
      List {
        Section {
          ForEach(viewModel.goals, id: \.id) { goal in
            GoalRow(goal: goal, onToggle: {
              viewModel.toggleCompleted(goal: goal)
            }, onTapContent: {
              #if !os(watchOS)
              editingGoal = goal
              #endif
            })
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                viewModel.deleteGoal(id: goal.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        } header: {
          Text("\(viewModel.goals.count) goal\(viewModel.goals.count == 1 ? "" : "s")")
        } footer: {
          Text("Changes sync in real time across all connected devices.")
            .font(.caption2)
        }

        #if os(watchOS)
        Section {
          Button("New Goal") {
            showCreateSheet = true
          }
          Button("Add Samples") {
            viewModel.createSampleGoals()
          }
          Button("Delete All", role: .destructive) {
            viewModel.deleteAllGoals()
          }
        }
        #endif
      }
      #if !os(watchOS)
      .listStyle(.insetGrouped)
      #endif
      .padding(.top, 24)
    }
  }
}

// MARK: - Goal Row

struct GoalRow: View {
  let goal: Goal
  let onToggle: () -> Void
  var onTapContent: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 12) {
      // Checkbox button — must use .borderless so the tap target
      // doesn't conflict with the row's own tap area in a List.
      Button(action: onToggle) {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isCompleted ? .green : .secondary)
          .font(.title3)
      }
      .buttonStyle(.borderless)

      // Content area — tappable for editing (non-watchOS)
      Button {
        onTapContent?()
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(goal.title)
              .font(.body)
              .strikethrough(isCompleted, color: .secondary)
              .foregroundStyle(isCompleted ? .secondary : .primary)

            if let difficulty = goal.difficulty {
              DifficultyBar(level: difficulty)
            }
          }

          Spacer()

          #if !os(watchOS)
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.quaternary)
          #endif
        }
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 2)
  }

  private var isCompleted: Bool {
    goal.completed ?? false
  }
}

// MARK: - Difficulty Bar

struct DifficultyBar: View {
  let level: Int

  var body: some View {
    HStack(spacing: 2) {
      ForEach(1...10, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(i <= level ? barColor : Color.gray.opacity(0.15))
          .frame(width: 3, height: 10)
      }
    }
  }

  private var barColor: Color {
    switch level {
    case 1...3: return .green
    case 4...6: return .orange
    default: return .red
    }
  }
}

// MARK: - Create Sheet

struct CreateGoalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var difficulty = 5

  let onSave: (String, Int) -> Void

  var body: some View {
    NavigationStack {
      Form {
        TextField("What's your goal?", text: $title)

        Stepper("Difficulty: \(difficulty)", value: $difficulty, in: 1...10)
      }
      .navigationTitle("New Goal")
      #if !os(watchOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      #else
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      #endif
    }
  }
}

// MARK: - Edit Sheet

struct EditGoalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var difficulty: Int

  let onSave: (String, Int) -> Void
  let onDelete: () -> Void

  init(goal: Goal, onSave: @escaping (String, Int) -> Void, onDelete: @escaping () -> Void) {
    _title = State(initialValue: goal.title)
    _difficulty = State(initialValue: goal.difficulty ?? 5)
    self.onSave = onSave
    self.onDelete = onDelete
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Title", text: $title)

        Stepper("Difficulty: \(difficulty)", value: $difficulty, in: 1...10)

        Section {
          Button("Delete Goal", role: .destructive) {
            onDelete()
            dismiss()
          }
        }
      }
      .navigationTitle("Edit Goal")
      #if !os(watchOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      #else
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(title, difficulty)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      #endif
    }
  }
}
