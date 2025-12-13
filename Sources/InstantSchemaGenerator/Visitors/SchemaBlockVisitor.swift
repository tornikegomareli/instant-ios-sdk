/// Schema Block Visitor for InstantDB Schema Generator
///
/// Parses the `InstantSchema { }` block to extract:
/// - Which entities are used in the schema
/// - Attribute configurations (.indexed(), .unique(), .optional())
/// - Link definitions between entities

import SwiftSyntax

/// Visits the InstantSchema DSL block to extract configurations and links.
class SchemaBlockVisitor: SyntaxVisitor {
  /// All available entity definitions from @InstantEntity structs
  private let allEntities: [String: EntitySchema]

  /// Only entities referenced in the schema block (via Entity(X.self))
  var entities: [String: EntitySchema] = [:]

  /// Extracted link definitions
  var links: [String: LinkSchema] = [:]

  /// Maps Swift type names to entity namespace names
  let entityTypeToName: [String: String]

  /// Tracks which Entity block we're currently inside
  private var currentEntityType: String?

  /// Prevents processing the same link node multiple times
  private var processedLinkNodes: Set<String> = []

  init(
    viewMode: SyntaxTreeViewMode,
    entities: [String: EntitySchema],
    entityTypeToName: [String: String]
  ) {
    self.allEntities = entities
    self.entityTypeToName = entityTypeToName
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    handleEntityCall(node)
    handleAttributeModifiers(node)
    handleLinkCall(node)
    return .visitChildren
  }

  override func visitPost(_ node: FunctionCallExprSyntax) {
    if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self),
       identifier.baseName.text == "Entity" {
      currentEntityType = nil
    }
  }

  /// Handles `Entity(Goal.self) { ... }` - adds entity to used entities
  private func handleEntityCall(_ node: FunctionCallExprSyntax) {
    guard let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self),
          identifier.baseName.text == "Entity",
          let firstArg = node.arguments.first,
          let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "self" else {
      return
    }

    let typeName = memberAccess.base?.description.trimmingCharacters(in: .whitespaces) ?? ""
    currentEntityType = typeName

    // Add this entity to used entities
    if let entityName = entityTypeToName[typeName],
       let entity = allEntities[entityName] {
      entities[entityName] = entity
    }
  }

  /// Handles `.indexed()`, `.unique()`, `.optional()` modifier calls
  private func handleAttributeModifiers(_ node: FunctionCallExprSyntax) {
    guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
      return
    }

    let methodName = memberAccess.declName.baseName.text

    guard methodName == "indexed" || methodName == "unique" || methodName == "optional",
          let attrName = extractAttrName(from: memberAccess.base),
          let entityType = currentEntityType,
          let entityName = entityTypeToName[entityType],
          var entity = entities[entityName],
          var attr = entity.attrs[attrName] else {
      return
    }

    if methodName == "indexed" {
      attr.config.indexed = true
    }
    if methodName == "unique" {
      attr.config.unique = true
      attr.config.indexed = true
    }
    if methodName == "optional" {
      attr.required = nil
    }

    entity.attrs[attrName] = attr
    entities[entityName] = entity
  }

  /// Handles `.to(Entity.self, "label")` calls to create links
  private func handleLinkCall(_ node: FunctionCallExprSyntax) {
    guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "to" else {
      return
    }

    let nodeId = "\(node.position.utf8Offset)"
    guard !processedLinkNodes.contains(nodeId) else { return }
    processedLinkNodes.insert(nodeId)

    guard let linkInfo = extractFullLinkChain(from: node),
          let fromEntityName = entityTypeToName[linkInfo.fromType],
          let toEntityName = entityTypeToName[linkInfo.toType] else {
      return
    }

    let linkName = "\(fromEntityName)_\(linkInfo.forwardLabel)"
    links[linkName] = LinkSchema(
      name: linkName,
      forward: LinkEndpointSchema(
        on: fromEntityName,
        has: linkInfo.cardinality,
        label: linkInfo.forwardLabel
      ),
      reverse: LinkEndpointSchema(
        on: toEntityName,
        has: linkInfo.cardinality == "many" ? "one" : "many",
        label: linkInfo.reverseLabel
      )
    )
  }
}

// MARK: - Link Extraction

extension SchemaBlockVisitor {
  struct LinkInfo {
    var fromType: String
    var forwardLabel: String
    var cardinality: String
    var toType: String
    var reverseLabel: String
  }

  private func extractFullLinkChain(from node: FunctionCallExprSyntax) -> LinkInfo? {
    var toType: String?
    var reverseLabel: String?
    var cardinality = "many"
    var fromType: String?
    var forwardLabel: String?

    for arg in node.arguments {
      if arg.label == nil {
        if let argMemberAccess = arg.expression.as(MemberAccessExprSyntax.self),
           argMemberAccess.declName.baseName.text == "self" {
          toType = argMemberAccess.base?.description.trimmingCharacters(in: .whitespaces)
        } else if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                  let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
          reverseLabel = segment.content.text
        }
      }
    }

    var currentExpr: ExprSyntax? = node.calledExpression.as(MemberAccessExprSyntax.self)?.base
    while let expr = currentExpr {
      if let funcCall = expr.as(FunctionCallExprSyntax.self) {
        if let memberAccess = funcCall.calledExpression.as(MemberAccessExprSyntax.self) {
          let methodName = memberAccess.declName.baseName.text
          if methodName == "hasMany" {
            cardinality = "many"
          } else if methodName == "hasOne" {
            cardinality = "one"
          }
          currentExpr = memberAccess.base
        } else if let declRef = funcCall.calledExpression.as(DeclReferenceExprSyntax.self),
                  declRef.baseName.text == "Link" {
          for arg in funcCall.arguments {
            if arg.label?.text == "from",
               let memberAccess = arg.expression.as(MemberAccessExprSyntax.self),
               memberAccess.declName.baseName.text == "self" {
              fromType = memberAccess.base?.description.trimmingCharacters(in: .whitespaces)
            } else if arg.label == nil,
                      let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                      let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
              forwardLabel = segment.content.text
            }
          }
          break
        } else {
          break
        }
      } else {
        break
      }
    }

    guard let from = fromType,
          let fwd = forwardLabel,
          let to = toType,
          let rev = reverseLabel else {
      return nil
    }

    return LinkInfo(
      fromType: from,
      forwardLabel: fwd,
      cardinality: cardinality,
      toType: to,
      reverseLabel: rev
    )
  }
}

// MARK: - Attribute Name Extraction

extension SchemaBlockVisitor {
  private func extractAttrName(from expr: ExprSyntax?) -> String? {
    guard let expr = expr else { return nil }

    if let funcCall = expr.as(FunctionCallExprSyntax.self) {
      if let identifier = funcCall.calledExpression.as(DeclReferenceExprSyntax.self),
         identifier.baseName.text == "Attr" {
        return extractKeyPathPropertyName(from: funcCall)
      }
      if let memberAccess = funcCall.calledExpression.as(MemberAccessExprSyntax.self) {
        return extractAttrName(from: memberAccess.base)
      }
    }

    if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
      return extractAttrName(from: memberAccess.base)
    }

    return nil
  }

  private func extractKeyPathPropertyName(from funcCall: FunctionCallExprSyntax) -> String? {
    guard let firstArg = funcCall.arguments.first,
          let keyPath = firstArg.expression.as(KeyPathExprSyntax.self),
          let component = keyPath.components.first,
          let propertyComponent = component.component.as(KeyPathPropertyComponentSyntax.self) else {
      return nil
    }
    return propertyComponent.declName.baseName.text
  }
}
