import Foundation

/// Represents the current authentication state
public enum AuthState: Equatable {

  /// Initial state, checking for stored tokens
  case loading

  /// User is signed in as guest
  case guest(User)

  /// User is authenticated with credentials
  case authenticated(User)

  /// No user is signed in
  case unauthenticated

  /// Current user, if any
  public var user: User? {
    switch self {
    case .guest(let user), .authenticated(let user):
      return user
    case .loading, .unauthenticated:
      return nil
    }
  }

  /// Whether a user is signed in (guest or authenticated)
  public var isSignedIn: Bool {
    user != nil
  }

  /// Whether the user is authenticated (not guest)
  public var isAuthenticated: Bool {
    if case .authenticated = self {
      return true
    }
    return false
  }

  /// Whether the user is a guest
  public var isGuest: Bool {
    if case .guest = self {
      return true
    }
    return false
  }
}

extension User {

  /// Whether this user is a guest user
  public var isGuest: Bool {
    email == nil && refreshToken != nil
  }
}
