import SwiftUI

struct GoalCard: View {
  let goal: Goal
  let onTap: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(goal.title)
            .font(.headline)
            .foregroundColor(.primary)
          Spacer()
          if let difficulty = goal.difficulty {
            DifficultyIndicator(level: difficulty)
          }
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Text("ID: \(goal.id)")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding()
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .cornerRadius(8)
      .shadow(color: Color.black.opacity(0.1), radius: 2)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
      }
    }
  }
}
