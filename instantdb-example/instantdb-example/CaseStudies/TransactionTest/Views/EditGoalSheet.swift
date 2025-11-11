import SwiftUI

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
