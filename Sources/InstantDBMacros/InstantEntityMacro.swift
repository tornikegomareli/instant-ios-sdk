import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InstantEntityMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract namespace from macro argument
        guard let argument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression,
              let stringLiteral = argument.as(StringLiteralExprSyntax.self),
              let namespace = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text else {
            throw MacroError.invalidNamespace
        }

        // Ensure declaration is a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }

        // Extract struct properties
        let members = structDecl.memberBlock.members
        let variables = members.compactMap { $0.decl.as(VariableDeclSyntax.self) }

        // Filter to get only stored properties (not computed)
        let storedProperties: [(name: String, type: String, isOptional: Bool)] = variables.compactMap { variable in
            // Skip computed properties
            guard variable.bindings.first?.accessorBlock == nil else { return nil }

            guard let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let type = binding.typeAnnotation?.type else {
                return nil
            }

            let typeDescription = type.trimmedDescription
            let isOptional = typeDescription.hasSuffix("?")

            return (name: identifier, type: typeDescription, isOptional: isOptional)
        }

        // Filter out 'id' property for parameter generation
        let propertiesWithoutId = storedProperties.filter { $0.name != "id" }

        var generatedMembers: [DeclSyntax] = []

        // 1. Generate namespace property
        generatedMembers.append(
            """
            static var namespace: String { "\(raw: namespace)" }
            """
        )

        // 2. Generate schemaAttributes for InstantEntitySchema
        let schemaAttributesCode = storedProperties.filter { $0.name != "id" }.map { prop in
            let baseType = prop.isOptional ? String(prop.type.dropLast()) : prop.type
            let instantType = mapSwiftTypeToInstantType(baseType)
            return "SchemaAttributeInfo(name: \"\(prop.name)\", dataType: .\(instantType), isOptional: \(prop.isOptional))"
        }.joined(separator: ",\n            ")

        generatedMembers.append(
            """
            static var schemaAttributes: [SchemaAttributeInfo] {
                [
                    \(raw: schemaAttributesCode)
                ]
            }
            """
        )

        // 2. Generate create method
        generatedMembers.append(contentsOf: try generateCreateMethod(
            namespace: namespace,
            properties: propertiesWithoutId
        ))

        // 3. Generate update methods
        generatedMembers.append(contentsOf: try generateUpdateMethods(
            namespace: namespace,
            structName: structDecl.name.text,
            properties: propertiesWithoutId
        ))

        // 4. Generate merge method
        generatedMembers.append(contentsOf: try generateMergeMethod(
            namespace: namespace,
            properties: propertiesWithoutId
        ))

        // 5. Generate delete method
        generatedMembers.append(
            """
            static func delete(id: String) -> TransactionChunk {
                TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["delete", namespace, id]]
                )
            }
            """
        )

        // 6. Generate link methods
        generatedMembers.append(contentsOf: generateLinkMethods())

        // 7. Generate unlink methods
        generatedMembers.append(contentsOf: generateUnlinkMethods())

        return generatedMembers
    }

    private static func generateCreateMethod(
        namespace: String,
        properties: [(name: String, type: String, isOptional: Bool)]
    ) throws -> [DeclSyntax] {
        // Build parameters
        let parameters = properties.map { prop in
            if prop.isOptional {
                return "\(prop.name): \(prop.type) = nil"
            } else {
                return "\(prop.name): \(prop.type)"
            }
        }.joined(separator: ",\n        ")

        // Build attributes dictionary
        let attributeAssignments = properties.map { prop in
            if prop.isOptional {
                return """
                if let \(prop.name) = \(prop.name) { attrs["\(prop.name)"] = \(prop.name) }
                """
            } else {
                return """
                attrs["\(prop.name)"] = \(prop.name)
                """
            }
        }.joined(separator: "\n        ")

        return [
            """
            static func create(
                id: String = UUID().uuidString,
                \(raw: parameters)
            ) -> TransactionChunk {
                var attrs: [String: Any] = [:]
                \(raw: attributeAssignments)

                return TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["update", namespace, id, attrs]]
                )
            }
            """
        ]
    }

    private static func generateUpdateMethods(
        namespace: String,
        structName: String,
        properties: [(name: String, type: String, isOptional: Bool)]
    ) throws -> [DeclSyntax] {
        // Build parameters with double optionals for nullable updates
        let parameters = properties.map { prop in
            if prop.isOptional {
                // Remove the trailing '?' to get base type
                let baseType = String(prop.type.dropLast())
                return "\(prop.name): \(baseType)?? = nil"
            } else {
                return "\(prop.name): \(prop.type)? = nil"
            }
        }.joined(separator: ",\n        ")

        // Build attribute assignments
        let attributeAssignments = properties.map { prop in
            if prop.isOptional {
                return """
                if let \(prop.name) = \(prop.name) {
                            if let value = \(prop.name) {
                                attrs["\(prop.name)"] = value
                            } else {
                                attrs["\(prop.name)"] = NSNull()
                            }
                        }
                """
            } else {
                return """
                if let \(prop.name) = \(prop.name) { attrs["\(prop.name)"] = \(prop.name) }
                """
            }
        }.joined(separator: "\n        ")

        return [
            // Update with parameters
            """
            static func update(
                id: String,
                \(raw: parameters)
            ) -> TransactionChunk {
                var attrs: [String: Any] = [:]
                \(raw: attributeAssignments)

                return TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["update", namespace, id, attrs]]
                )
            }
            """,

            // Update with instance
            """
            static func update(_ entity: \(raw: structName)) -> TransactionChunk {
                let encoder = JSONEncoder()
                let data = (try? encoder.encode(entity)) ?? Data()
                let attrs = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

                return TransactionChunk(
                    namespace: namespace,
                    id: entity.id,
                    ops: [["update", namespace, entity.id, attrs]]
                )
            }
            """
        ]
    }

    private static func generateMergeMethod(
        namespace: String,
        properties: [(name: String, type: String, isOptional: Bool)]
    ) throws -> [DeclSyntax] {
        let parameters = properties.map { prop in
            if prop.isOptional {
                let baseType = String(prop.type.dropLast())
                return "\(prop.name): \(baseType)?? = nil"
            } else {
                return "\(prop.name): \(prop.type)? = nil"
            }
        }.joined(separator: ",\n        ")

        let attributeAssignments = properties.map { prop in
            if prop.isOptional {
                return """
                if let \(prop.name) = \(prop.name) {
                            if let value = \(prop.name) {
                                attrs["\(prop.name)"] = value
                            } else {
                                attrs["\(prop.name)"] = NSNull()
                            }
                        }
                """
            } else {
                return """
                if let \(prop.name) = \(prop.name) { attrs["\(prop.name)"] = \(prop.name) }
                """
            }
        }.joined(separator: "\n        ")

        return [
            """
            static func merge(
                id: String,
                \(raw: parameters)
            ) -> TransactionChunk {
                var attrs: [String: Any] = [:]
                \(raw: attributeAssignments)

                return TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["merge", namespace, id, attrs]]
                )
            }
            """
        ]
    }

    private static func generateLinkMethods() -> [DeclSyntax] {
        return [
            """
            static func link(id: String, _ relationship: String, to ids: [String]) -> TransactionChunk {
                TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["link", namespace, id, [relationship: ids]]]
                )
            }
            """,

            """
            static func link(id: String, _ relationship: String, to linkedId: String) -> TransactionChunk {
                link(id: id, relationship, to: [linkedId])
            }
            """
        ]
    }

    private static func generateUnlinkMethods() -> [DeclSyntax] {
        return [
            """
            static func unlink(id: String, _ relationship: String, from ids: [String]) -> TransactionChunk {
                TransactionChunk(
                    namespace: namespace,
                    id: id,
                    ops: [["unlink", namespace, id, [relationship: ids]]]
                )
            }
            """,

            """
            static func unlink(id: String, _ relationship: String, from linkedId: String) -> TransactionChunk {
                unlink(id: id, relationship, from: [linkedId])
            }
            """
        ]
    }

    // MARK: - ExtensionMacro conformance

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Create extension that conforms to InstantEntity, InstantEntitySchema, Identifiable, and Codable
        let extensionDecl: DeclSyntax = """
        extension \(type.trimmed): InstantEntity, InstantEntitySchema, Identifiable, Codable {}
        """

        guard let extensionDeclSyntax = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionDeclSyntax]
    }
}

enum MacroError: Error, CustomStringConvertible {
    case invalidNamespace
    case notAStruct

    var description: String {
        switch self {
        case .invalidNamespace:
            return "@InstantEntity requires a string literal namespace argument"
        case .notAStruct:
            return "@InstantEntity can only be applied to structs"
        }
    }
}

func mapSwiftTypeToInstantType(_ swiftType: String) -> String {
    switch swiftType {
    case "String":
        return "string"
    case "Int", "Double", "Float", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "CGFloat":
        return "number"
    case "Bool":
        return "boolean"
    case "Date":
        return "date"
    default:
        return "json"
    }
}
