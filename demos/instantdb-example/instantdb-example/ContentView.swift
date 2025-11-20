//
//  ContentView.swift
//  instantdb-example
//
//  Created by Tornike Gomareli on 22.10.25.
//

import SwiftUI
import InstantDB

struct ContentView: View {
  @EnvironmentObject var db: InstantClient
  @EnvironmentObject var authManager: AuthManager
  @StateObject private var viewModel = InstantDBViewModel()

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 20) {
          connectionStatusView

          Divider()

          statsView

          Divider()

          actionsView

          LogView(title: "Connection Logs", logs: $viewModel.logs, height: 200)
        }
        .padding()
        .padding(.bottom, 60)
      }
      .navigationTitle("InstantDB Test")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        viewModel.setup(db: db, authManager: authManager)
      }
    }
  }

  private var connectionStatusView: some View {
    VStack(spacing: 12) {
      Text(viewModel.statusEmoji)
        .font(.system(size: 60))

      Text(viewModel.statusText)
        .font(.headline)

      if let user = viewModel.authState.user {
        Text(user.email ?? "Guest User")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if let sessionID = viewModel.sessionID {
        Text("Session: \(sessionID.prefix(8))...")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(12)
  }
  
  private var statsView: some View {
    HStack(spacing: 12) {
      StatItem(
        icon: "person.circle.fill",
        label: "Auth Status",
        value: viewModel.authState.isAuthenticated ? "Authenticated" : viewModel.authState.isGuest ? "Guest" : "Not signed in",
        color: viewModel.authState.isAuthenticated ? .green : viewModel.authState.isGuest ? .orange : .gray
      )

      StatItem(
        icon: "doc.text.fill",
        label: "Attributes",
        value: "\(viewModel.attributesCount)",
        color: .blue
      )
    }
  }
  
  private var actionsView: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button(action: { viewModel.connect() }) {
          Label("Connect", systemImage: "play.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        
        Button(action: { viewModel.disconnect() }) {
          Label("Disconnect", systemImage: "stop.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
      }
      
      NavigationLink(destination: TransactionTestView()) {
        Label("Simple Transaction, Query Test", systemImage: "flask.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(db.connectionState != .authenticated)
    }
  }
}

struct StatItem: View {
  let icon: String
  let label: String
  let value: String
  let color: Color

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(color)

      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)

      Text(value)
        .font(.caption)
        .fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .padding(.horizontal, 8)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .cornerRadius(10)
  }
}

#Preview {
  ContentView()
}
