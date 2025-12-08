import Foundation

public struct SchemaAttribute: Sendable {
  public let name: String
  public let dataType: InstantDataType
  public private(set) var isIndexed: Bool = false
  public private(set) var isUnique: Bool = false
  public private(set) var isOptional: Bool = false

  public init(_ name: String, _ dataType: InstantDataType) {
    self.name = name
    self.dataType = dataType
  }

  public func indexed() -> SchemaAttribute {
    var copy = self
    copy.isIndexed = true
    return copy
  }

  public func unique() -> SchemaAttribute {
    var copy = self
    copy.isUnique = true
    copy.isIndexed = true
    return copy
  }

  public func optional() -> SchemaAttribute {
    var copy = self
    copy.isOptional = true
    return copy
  }
}
