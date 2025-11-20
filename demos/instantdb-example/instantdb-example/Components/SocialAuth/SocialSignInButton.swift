import SwiftUI

/// Full-width social sign-in button with brand styling
struct SocialSignInButton: View {
  let provider: SocialProvider
  let action: () -> Void
  var isLoading: Bool = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: provider.foregroundColor))
            .frame(width: 20, height: 20)
        } else {
          if let imageName = provider.imageName {
            Image(imageName)
              .resizable()
              .scaledToFit()
              .frame(width: 20, height: 20)
          } else if let systemIcon = provider.systemIcon {
            Image(systemName: systemIcon)
              .font(.system(size: 20))
              .foregroundStyle(provider.foregroundColor)
          }
        }

        Text("Continue with \(provider.displayName)")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(provider.foregroundColor)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(provider.backgroundColor)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(provider.borderColor ?? Color.clear, lineWidth: 1)
      )
      .cornerRadius(8)
      .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    .disabled(isLoading)
  }
}

/// Compact social sign-in button (icon + optional label)
struct CompactSocialSignInButton: View {
  let provider: SocialProvider
  let action: () -> Void
  var isLoading: Bool = false
  var showLabel: Bool = true

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: provider.foregroundColor))
            .frame(width: 18, height: 18)
        } else {
          if let imageName = provider.imageName {
            Image(imageName)
              .resizable()
              .scaledToFit()
              .frame(width: 18, height: 18)
          } else if let systemIcon = provider.systemIcon {
            Image(systemName: systemIcon)
              .font(.system(size: 18))
              .foregroundStyle(provider.foregroundColor)
          }
        }

        if showLabel {
          Text(provider.displayName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(provider.foregroundColor)
        }
      }
      .frame(maxWidth: showLabel ? .infinity : nil)
      .frame(height: 44)
      .padding(.horizontal, showLabel ? 16 : 12)
      .background(provider.backgroundColor)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(provider.borderColor ?? Color.clear, lineWidth: 1)
      )
      .cornerRadius(8)
      .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
    .disabled(isLoading)
  }
}

/// Circular social sign-in button (icon only)
struct CircularSocialSignInButton: View {
  let provider: SocialProvider
  let action: () -> Void
  var isLoading: Bool = false
  var size: CGFloat = 56

  var body: some View {
    Button(action: action) {
      ZStack {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: provider.foregroundColor))
            .frame(width: size * 0.4, height: size * 0.4)
        } else {
          if let imageName = provider.imageName {
            Image(imageName)
              .resizable()
              .scaledToFit()
              .frame(width: size * 0.45, height: size * 0.45)
          } else if let systemIcon = provider.systemIcon {
            Image(systemName: systemIcon)
              .font(.system(size: size * 0.45))
              .foregroundStyle(provider.foregroundColor)
          }
        }
      }
      .frame(width: size, height: size)
      .background(provider.backgroundColor)
      .overlay(
        Circle()
          .stroke(provider.borderColor ?? Color.clear, lineWidth: 1)
      )
      .clipShape(Circle())
      .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    .disabled(isLoading)
  }
}
