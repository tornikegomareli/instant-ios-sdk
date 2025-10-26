import Foundation
import Security

/// Secure storage using iOS Keychain
public final class KeychainStorage {

  private let service: String

  public init(service: String = "com.instantdb.sdk") {
    self.service = service
  }

  /// Save a Codable value to keychain
  public func save<T: Codable>(_ value: T, forKey key: String) throws {
    let data = try JSONEncoder().encode(value)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    SecItemDelete(query as CFDictionary)

    let status = SecItemAdd(query as CFDictionary, nil)

    guard status == errSecSuccess else {
      throw KeychainError.saveFailed(status: status)
    }
  }

  /// Retrieve a Codable value from keychain
  public func retrieve<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status != errSecItemNotFound else {
      return nil
    }

    guard status == errSecSuccess else {
      throw KeychainError.retrieveFailed(status: status)
    }

    guard let data = result as? Data else {
      throw KeychainError.invalidData
    }

    return try JSONDecoder().decode(type, from: data)
  }

  /// Delete a value from keychain
  public func delete(forKey key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.deleteFailed(status: status)
    }
  }

  /// Clear all values for this service
  public func clear() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.clearFailed(status: status)
    }
  }
}

public enum KeychainError: Error, LocalizedError {
  case saveFailed(status: OSStatus)
  case retrieveFailed(status: OSStatus)
  case deleteFailed(status: OSStatus)
  case clearFailed(status: OSStatus)
  case invalidData

  public var errorDescription: String? {
    switch self {
    case .saveFailed(let status):
      return "Failed to save to keychain: \(status)"
    case .retrieveFailed(let status):
      return "Failed to retrieve from keychain: \(status)"
    case .deleteFailed(let status):
      return "Failed to delete from keychain: \(status)"
    case .clearFailed(let status):
      return "Failed to clear keychain: \(status)"
    case .invalidData:
      return "Invalid data retrieved from keychain"
    }
  }
}
