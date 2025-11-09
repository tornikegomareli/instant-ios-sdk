import SwiftUI
import InstantDB

struct QueryTestView: View {
  @EnvironmentObject var db: InstantClient
  @State private var queryResult = ""
  @State private var isLoading = false
  @State private var error: String?
  @State private var unsubscribe: (() -> Void)?

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        // Connection Status
        HStack {
          Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
          Text("Status: \(statusText)")
        }
        .padding()

        // Query Tests
        VStack(alignment: .leading, spacing: 15) {
          Text("Query Tests")
            .font(.headline)

          Button(action: subscribeToGoals) {
            Label("Subscribe to Goals", systemImage: "arrow.down.circle")
          }
          .buttonStyle(.borderedProminent)

          Button(action: subscribeToTodos) {
            Label("Subscribe to Todos", systemImage: "checklist")
          }
          .buttonStyle(.borderedProminent)

          Button(action: subscribeWithRelationships) {
            Label("Goals with Todos", systemImage: "link")
          }
          .buttonStyle(.borderedProminent)

          if unsubscribe != nil {
            Button(action: unsubscribeFromQuery) {
              Label("Unsubscribe", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()

        // Results
        VStack(alignment: .leading, spacing: 10) {
          Text("Query Result:")
            .font(.headline)

          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if let error = error {
            Text("Error: \(error)")
              .foregroundColor(.red)
              .font(.system(.caption, design: .monospaced))
          } else {
            ScrollView {
              Text(queryResult.isEmpty ? "No data" : queryResult)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
          }
        }
        .padding()

        Spacer()
      }
      .navigationTitle("Query Tests")
    }
    .onAppear {
      if db.connectionState == .disconnected {
        db.connect()
      }
    }
  }

  private var statusColor: Color {
    switch db.connectionState {
    case .authenticated:
      return .green
    case .connected:
      return .orange
    case .connecting:
      return .yellow
    case .disconnected:
      return .red
    case .error:
      return .red
    }
  }

  private var statusText: String {
    switch db.connectionState {
    case .authenticated:
      return "Authenticated"
    case .connected:
      return "Connected"
    case .connecting:
      return "Connecting..."
    case .disconnected:
      return "Disconnected"
    case .error(let err):
      return "Error: \(err.localizedDescription)"
    }
  }

  private func subscribeToGoals() {
    error = nil
    queryResult = ""

    do {
      unsubscribe?()
      unsubscribe = try db.subscribeQuery(["goals": [:]]) { result in
        DispatchQueue.main.async {
          self.isLoading = result.isLoading

          if let err = result.error {
            self.error = err.localizedDescription
          } else {
            // Pretty print the result
            if let data = try? JSONSerialization.data(
              withJSONObject: result.data,
              options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: data, encoding: .utf8) {
              self.queryResult = string
            } else {
              self.queryResult = "\(result.data)"
            }
          }
        }
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func subscribeToTodos() {
    error = nil
    queryResult = ""

    do {
      unsubscribe?()
      unsubscribe = try db.subscribeQuery(["todos": [:]]) { result in
        DispatchQueue.main.async {
          self.isLoading = result.isLoading

          if let err = result.error {
            self.error = err.localizedDescription
          } else {
            // Pretty print the result
            if let data = try? JSONSerialization.data(
              withJSONObject: result.data,
              options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: data, encoding: .utf8) {
              self.queryResult = string
            } else {
              self.queryResult = "\(result.data)"
            }
          }
        }
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func subscribeWithRelationships() {
    error = nil
    queryResult = ""

    do {
      unsubscribe?()
      // Query goals with their todos
      let query: [String: Any] = [
        "goals": [
          "todos": [:]
        ]
      ]

      unsubscribe = try db.subscribeQuery(query) { result in
        DispatchQueue.main.async {
          self.isLoading = result.isLoading

          if let err = result.error {
            self.error = err.localizedDescription
          } else {
            // Pretty print the result
            if let data = try? JSONSerialization.data(
              withJSONObject: result.data,
              options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: data, encoding: .utf8) {
              self.queryResult = string
            } else {
              self.queryResult = "\(result.data)"
            }
          }
        }
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func unsubscribeFromQuery() {
    unsubscribe?()
    unsubscribe = nil
    queryResult = "Unsubscribed"
    error = nil
    isLoading = false
  }
}

#Preview {
  QueryTestView()
    .environmentObject(InstantClient(appID: AppConfig.instantAppID))
}