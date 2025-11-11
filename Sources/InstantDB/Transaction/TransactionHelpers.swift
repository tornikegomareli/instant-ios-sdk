import Foundation

/// Generate a new UUID for use as an entity ID
/// - Returns: A UUID string
///
/// Example:
/// ```swift
/// let goalId = newId()
/// db.tx.goals[goalId].update(["title": "Get fit"])
/// ```
public func newId() -> String {
  UUID().uuidString
}

/// Create a lookup reference to find an entity by a unique attribute
/// - Parameters:
///   - attribute: The attribute name (e.g., "email", "username")
///   - value: The value to look up
/// - Returns: A lookup string that can be used in place of an ID
///
/// Example:
/// ```swift
/// db.tx.users[lookup("email", "joe@example.com")].update(["name": "Joe"])
/// ```
public func lookup(_ attribute: String, _ value: Any) -> String {
  let valueData = try? JSONSerialization.data(withJSONObject: value, options: [])
  let valueString = valueData.flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
  return "lookup__\(attribute)__\(valueString)"
}

/// Check if a string is a lookup reference
/// - Parameter str: The string to check
/// - Returns: True if the string is a lookup reference
func isLookup(_ str: String) -> Bool {
  str.hasPrefix("lookup__")
}

/// Parse a lookup string into its components
/// - Parameter str: The lookup string
/// - Returns: A tuple of (attribute, value) if valid, nil otherwise
func parseLookup(_ str: String) -> (attribute: String, value: Any)? {
  guard isLookup(str) else { return nil }

  let parts = str.components(separatedBy: "__")
  guard parts.count >= 3 else { return nil }

  let attribute = parts[1]
  let valueJSON = parts[2...].joined(separator: "__")

  guard let valueData = valueJSON.data(using: .utf8),
        let value = try? JSONSerialization.jsonObject(with: valueData, options: []) else {
    return (attribute, valueJSON)
  }

  return (attribute, value)
}
