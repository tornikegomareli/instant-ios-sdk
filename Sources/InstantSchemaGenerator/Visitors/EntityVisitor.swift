/// Entity Visitor for InstantDB Schema Generator
///
/// Extracts entity definitions from Swift source files by finding
/// structs decorated with `@InstantEntity` attribute.

import SwiftSyntax

/// Visits Swift syntax tree to extract `@InstantEntity` struct definitions.
///
/// This visitor finds structs like:
/// ```swift
/// @InstantEntity("users")
/// struct User {
///     var id: String
///     var email: String
///     var name: String
/// }
/// ```
///
/// And extracts:
/// - Entity name from the attribute argument ("users")
/// - Type name from the struct name ("User")
/// - Attributes from the struct properties (email, name - excluding id)
class EntityVisitor: SyntaxVisitor {
  /// Collected entity definitions
  var entities: [EntitySchema] = []

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    guard hasInstantEntityAttribute(node) else {
      return .visitChildren
    }

    let typeName = node.name.text
    let entityName = extractEntityName(from: node) ?? typeName
    let attributes = extractAttributes(from: node)

    entities.append(EntitySchema(
      name: entityName,
      typeName: typeName,
      attrs: attributes
    ))

    return .visitChildren
  }

  /// Checks if the struct has an `@InstantEntity` attribute.
  private func hasInstantEntityAttribute(_ node: StructDeclSyntax) -> Bool {
    node.attributes.contains { attr in
      if case .attribute(let attribute) = attr {
        let name = attribute.attributeName.description.trimmingCharacters(in: .whitespaces)
        return name == "InstantEntity"
      }
      return false
    }
  }

  /// Extracts the entity name from `@InstantEntity("name")` attribute.
  private func extractEntityName(from node: StructDeclSyntax) -> String? {
    for attr in node.attributes {
      if case .attribute(let attribute) = attr,
         attribute.attributeName.description.trimmingCharacters(in: .whitespaces) == "InstantEntity",
         let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
         let firstArg = arguments.first,
         let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
         let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
        return segment.content.text
      }
    }
    return nil
  }

  /// Extracts attributes from struct properties, excluding `id`.
  private func extractAttributes(from node: StructDeclSyntax) -> [String: AttributeSchema] {
    var attributes: [String: AttributeSchema] = [:]

    for member in node.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
            let typeAnnotation = binding.typeAnnotation else {
        continue
      }

      let name = identifier.identifier.text
      if name == "id" { continue }

      let typeString = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
      let isOptional = typeString.hasSuffix("?")
      let baseType = isOptional ? String(typeString.dropLast()) : typeString
      let valueType = TypeMapper.swiftTypeToInstant(baseType)

      attributes[name] = AttributeSchema(
        valueType: valueType,
        config: AttributeConfig(),
        required: isOptional ? nil : true
      )
    }

    return attributes
  }
}
