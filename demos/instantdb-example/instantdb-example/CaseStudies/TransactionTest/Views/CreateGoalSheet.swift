import SwiftUI

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
