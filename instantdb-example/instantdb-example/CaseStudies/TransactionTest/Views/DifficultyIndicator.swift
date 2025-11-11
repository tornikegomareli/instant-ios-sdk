import SwiftUI

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
