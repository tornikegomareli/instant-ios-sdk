import Foundation

public struct SchemaEntity: Sendable {
  public let name: String
  public let attributes: [SchemaAttribute]

  public init(_ name: String, @SchemaAttributeBuilder attributes: () -> [SchemaAttribute]) {
    self.name = name
    self.attributes = attributes()
  }

  public init(_ name: String, attributes: [SchemaAttribute]) {
    self.name = name
    self.attributes = attributes
  }
}

@resultBuilder
public struct SchemaAttributeBuilder {
  public static func buildBlock(_ components: [SchemaAttribute]...) -> [SchemaAttribute] {
    components.flatMap { $0 }
  }

  public static func buildArray(_ components: [[SchemaAttribute]]) -> [SchemaAttribute] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [SchemaAttribute]?) -> [SchemaAttribute] {
    component ?? []
  }

  public static func buildEither(first component: [SchemaAttribute]) -> [SchemaAttribute] {
    component
  }

  public static func buildEither(second component: [SchemaAttribute]) -> [SchemaAttribute] {
    component
  }

  public static func buildExpression(_ expression: SchemaAttribute) -> [SchemaAttribute] {
    [expression]
  }
}
