import SwiftUI
import InstantDB

struct PaginationTestView: View {
  @EnvironmentObject var db: InstantClient
  @StateObject private var viewModel = PaginationTestViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        controlsSection
        paginationInfoSection
        goalsListSection
        actionsSection
        LogView(title: "Pagination Logs", logs: $viewModel.logs, height: 200)
      }
      .padding()
    }
    .navigationTitle("Cursor Pagination")
    .onAppear {
      viewModel.setup(db: db)
    }
  }

  private var controlsSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Page Size:")
          .font(.subheadline)

        Picker("Page Size", selection: Binding(
          get: { viewModel.pageSize },
          set: { viewModel.changePageSize($0) }
        )) {
          Text("3").tag(3)
          Text("5").tag(5)
          Text("10").tag(10)
        }
        .pickerStyle(.segmented)
      }

      HStack {
        Text("Sort Order:")
          .font(.subheadline)

        Spacer()

        Button(action: { viewModel.toggleSortOrder() }) {
          HStack {
            Text(viewModel.sortOrder == .asc ? "A → Z" : "Z → A")
            Image(systemName: viewModel.sortOrder == .asc ? "arrow.up" : "arrow.down")
          }
        }
        .buttonStyle(.bordered)
      }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(12)
  }

  private var paginationInfoSection: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Page \(viewModel.currentPage)")
          .font(.headline)

        Spacer()

        Text("\(viewModel.goals.count) items")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 16) {
        Button(action: { viewModel.loadPreviousPage() }) {
          HStack {
            Image(systemName: "chevron.left")
            Text("Previous")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasPreviousPage)

        Button(action: { viewModel.loadNextPage() }) {
          HStack {
            Text("Next")
            Image(systemName: "chevron.right")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasNextPage)
      }

      HStack(spacing: 20) {
        Label(viewModel.hasPreviousPage ? "Has Previous" : "No Previous",
              systemImage: viewModel.hasPreviousPage ? "checkmark.circle.fill" : "xmark.circle")
          .font(.caption)
          .foregroundStyle(viewModel.hasPreviousPage ? .green : .secondary)

        Label(viewModel.hasNextPage ? "Has Next" : "No Next",
              systemImage: viewModel.hasNextPage ? "checkmark.circle.fill" : "xmark.circle")
          .font(.caption)
          .foregroundStyle(viewModel.hasNextPage ? .green : .secondary)
      }
    }
    .padding()
    .background(Color.blue.opacity(0.1))
    .cornerRadius(12)
  }

  private var goalsListSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Goals")
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
        VStack(spacing: 8) {
          Image(systemName: "tray")
            .font(.largeTitle)
            .foregroundColor(.gray)
          Text("No goals on this page")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        ForEach(viewModel.goals.indices, id: \.self) { index in
          PaginationGoalRow(goal: viewModel.goals[index], index: index + 1)
        }
      }
    }
    .padding()
    .background(Color.purple.opacity(0.05))
    .cornerRadius(12)
  }

  private var actionsSection: some View {
    VStack(spacing: 12) {
      Text("Test Actions")
        .font(.headline)

      HStack(spacing: 12) {
        Button(action: { viewModel.createSampleGoals() }) {
          Label("Create 13 Goals", systemImage: "plus.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.green)

        Button(action: { viewModel.deleteAllGoals() }) {
          Label("Delete All", systemImage: "trash.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
      }

      Button(action: { viewModel.loadFirstPage() }) {
        Label("Refresh / Go to First Page", systemImage: "arrow.counterclockwise")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
    }
    .padding()
    .background(Color.orange.opacity(0.1))
    .cornerRadius(12)
  }
}

struct PaginationGoalRow: View {
  let goal: Goal
  let index: Int

  var body: some View {
    HStack {
      Text("\(index).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(goal.title)
          .font(.subheadline)
          .fontWeight(.medium)

        HStack(spacing: 8) {
          if let difficulty = goal.difficulty {
            Label("\(difficulty)", systemImage: "star.fill")
              .font(.caption2)
              .foregroundStyle(.orange)
          }

          if let completed = goal.completed {
            Label(completed ? "Done" : "Pending",
                  systemImage: completed ? "checkmark.circle.fill" : "circle")
              .font(.caption2)
              .foregroundStyle(completed ? .green : .gray)
          }
        }
      }

      Spacer()

      Text(goal.id.prefix(6) + "...")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .monospaced()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color.white.opacity(0.5))
    .cornerRadius(8)
  }
}

#Preview {
  NavigationView {
    PaginationTestView()
      .environmentObject(InstantClient(appID: AppConfig.instantAppID))
  }
}
