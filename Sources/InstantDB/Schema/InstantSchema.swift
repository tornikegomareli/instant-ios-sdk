import Foundation

public struct InstantSchema: Sendable {
  public let entities: [SchemaEntity]
  public let links: [SchemaLink]

  public init(@InstantSchemaBuilder content: () -> InstantSchemaContent) {
    let schemaContent = content()
    self.entities = schemaContent.entities
    self.links = schemaContent.links
  }

  public init(entities: [SchemaEntity], links: [SchemaLink] = []) {
    self.entities = entities
    self.links = links
  }
}

public struct InstantSchemaContent: Sendable {
  public var entities: [SchemaEntity] = []
  public var links: [SchemaLink] = []

  public init(entities: [SchemaEntity] = [], links: [SchemaLink] = []) {
    self.entities = entities
    self.links = links
  }
}

@resultBuilder
public struct InstantSchemaBuilder {
  public static func buildBlock(_ components: InstantSchemaComponent...) -> InstantSchemaContent {
    var content = InstantSchemaContent()
    for component in components {
      switch component {
      case .entity(let entity):
        content.entities.append(entity)
      case .link(let link):
        content.links.append(link)
      }
    }
    return content
  }

  public static func buildExpression(_ expression: SchemaEntity) -> InstantSchemaComponent {
    .entity(expression)
  }

  public static func buildExpression(_ expression: LinkBuilder) -> InstantSchemaComponent {
    if let link = expression.build() {
      return .link(link)
    }
    fatalError("Invalid link builder - missing reverse endpoint. Use .to(entity, label)")
  }

  public static func buildExpression(_ expression: SchemaLink) -> InstantSchemaComponent {
    .link(expression)
  }

  public static func buildExpression<E: InstantEntitySchema>(_ expression: TypedEntity<E>) -> InstantSchemaComponent {
    .entity(expression.toSchemaEntity())
  }

  public static func buildExpression<From: InstantEntitySchema, To: InstantEntitySchema>(
    _ expression: TypedLinkBuilder<From, To>
  ) -> InstantSchemaComponent {
    if let link = expression.build() {
      return .link(link)
    }
    fatalError("Invalid typed link builder - missing reverse endpoint. Use .to(EntityType.self, label)")
  }

  public static func buildArray(_ components: [InstantSchemaComponent]) -> InstantSchemaContent {
    var content = InstantSchemaContent()
    for component in components {
      switch component {
      case .entity(let entity):
        content.entities.append(entity)
      case .link(let link):
        content.links.append(link)
      }
    }
    return content
  }

  public static func buildOptional(_ component: InstantSchemaContent?) -> InstantSchemaContent {
    component ?? InstantSchemaContent()
  }
}

public enum InstantSchemaComponent {
  case entity(SchemaEntity)
  case link(SchemaLink)
}
