import SwiftUI

enum LogLevel {
  case success
  case error
  case info
  case warning
  case debug

  var color: Color {
    switch self {
    case .success: return .green
    case .error: return .red
    case .info: return .blue
    case .warning: return .orange
    case .debug: return .secondary
    }
  }

  static func from(_ message: String) -> (level: LogLevel, cleanMessage: String) {
    if message.contains("[SUCCESS]") {
      return (.success, message.replacingOccurrences(of: "[SUCCESS]", with: "").trimmingCharacters(in: .whitespaces))
    } else if message.contains("[ERROR]") {
      return (.error, message.replacingOccurrences(of: "[ERROR]", with: "").trimmingCharacters(in: .whitespaces))
    } else if message.contains("[INFO]") {
      return (.info, message.replacingOccurrences(of: "[INFO]", with: "").trimmingCharacters(in: .whitespaces))
    } else if message.contains("[WARNING]") {
      return (.warning, message.replacingOccurrences(of: "[WARNING]", with: "").trimmingCharacters(in: .whitespaces))
    } else if message.contains("[DEBUG]") {
      return (.debug, message.replacingOccurrences(of: "[DEBUG]", with: "").trimmingCharacters(in: .whitespaces))
    }
    return (.info, message)
  }
}

struct LogView: View {
  @Binding var logs: [String]
  let title: String
  let height: CGFloat

  init(title: String = "Log", logs: Binding<[String]>, height: CGFloat = 150) {
    self.title = title
    self._logs = logs
    self.height = height
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()

        Button(action: copyLogs) {
          Label("Copy", systemImage: "doc.on.doc")
            .font(.caption)
        }
        .buttonStyle(.bordered)

        if !logs.isEmpty {
          Button(action: { logs.removeAll() }) {
            Text("Clear")
              .font(.caption)
          }
          .buttonStyle(.bordered)
        }
      }

      ScrollView {
        ScrollViewReader { proxy in
          VStack(alignment: .leading, spacing: 4) {
            if logs.isEmpty {
              Text("No logs yet")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
            } else {
              ForEach(Array(logs.suffix(20).enumerated()), id: \.offset) { index, log in
                let parsed = LogLevel.from(log)
                Text(parsed.cleanMessage)
                  .font(.system(.caption2, design: .monospaced))
                  .foregroundColor(parsed.level.color)
                  .padding(.vertical, 2)
                  .id(index)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .onChange(of: logs.count) { _ in
            if !logs.isEmpty {
              withAnimation {
                proxy.scrollTo(logs.suffix(20).count - 1, anchor: .bottom)
              }
            }
          }
        }
      }
      .frame(height: height)
      .padding(8)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .cornerRadius(8)
    }
    .padding()
    .background(Color.purple.opacity(0.05))
    .cornerRadius(12)
  }

  private func copyLogs() {
    let logText = logs.reversed().joined(separator: "\n")
    UIPasteboard.general.string = logText
  }
}
