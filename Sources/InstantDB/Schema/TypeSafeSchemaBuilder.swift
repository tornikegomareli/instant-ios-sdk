import Foundation

public struct TypedEntity<E: InstantEntitySchema>: Sendable {
    public let entityType: E.Type
    public let attributeConfigs: [TypedAttributeConfig]

    public init(_ type: E.Type, @TypedAttributeBuilder configs: () -> [TypedAttributeConfig] = { [] }) {
        self.entityType = type
        self.attributeConfigs = configs()
    }

    public func toSchemaEntity() -> SchemaEntity {
        var configMap: [String: TypedAttributeConfig] = [:]
        for config in attributeConfigs {
            configMap[config.name] = config
        }

        let attributes = E.schemaAttributes.map { info -> SchemaAttribute in
            if let config = configMap[info.name] {
                return SchemaAttribute(
                    info.name,
                    info.dataType,
                    isOptional: info.isOptional || config.isOptional,
                    isIndexed: config.isIndexed,
                    isUnique: config.isUnique
                )
            } else {
                return SchemaAttribute(
                    info.name,
                    info.dataType,
                    isOptional: info.isOptional
                )
            }
        }

        return SchemaEntity(E.namespace, attributes: attributes)
    }
}

public struct TypedAttributeConfig: Sendable {
    public let name: String
    public var isIndexed: Bool = false
    public var isUnique: Bool = false
    public var isOptional: Bool = false

    public init(name: String) {
        self.name = name
    }

    public func indexed() -> TypedAttributeConfig {
        var copy = self
        copy.isIndexed = true
        return copy
    }

    public func unique() -> TypedAttributeConfig {
        var copy = self
        copy.isUnique = true
        return copy
    }

    public func optional() -> TypedAttributeConfig {
        var copy = self
        copy.isOptional = true
        return copy
    }
}

public func Attr<E: InstantEntitySchema, V>(_ keyPath: KeyPath<E, V>) -> TypedAttributeConfig {
    let mirror = Mirror(reflecting: keyPath)
    let name = extractPropertyName(from: keyPath) ?? "unknown"
    return TypedAttributeConfig(name: name)
}

private func extractPropertyName<Root, Value>(from keyPath: KeyPath<Root, Value>) -> String? {
    let description = String(describing: keyPath)
    if let lastDot = description.lastIndex(of: ".") {
        return String(description[description.index(after: lastDot)...])
    }
    return description
}

@resultBuilder
public struct TypedAttributeBuilder {
    public static func buildBlock(_ components: TypedAttributeConfig...) -> [TypedAttributeConfig] {
        components
    }

    public static func buildExpression(_ expression: TypedAttributeConfig) -> TypedAttributeConfig {
        expression
    }

    public static func buildOptional(_ component: [TypedAttributeConfig]?) -> [TypedAttributeConfig] {
        component ?? []
    }

    public static func buildArray(_ components: [[TypedAttributeConfig]]) -> [TypedAttributeConfig] {
        components.flatMap { $0 }
    }
}

public struct TypedLinkBuilder<From: InstantEntitySchema, To: InstantEntitySchema>: Sendable {
    private let fromType: From.Type
    private let forwardLabel: String
    private var forwardCardinality: Cardinality = .one
    private var forwardRequired: Bool = false
    private var forwardOnDelete: OnDeleteAction?

    private var toType: To.Type?
    private var reverseLabel: String?
    private var reverseCardinality: Cardinality = .many
    private var reverseOnDelete: OnDeleteAction?

    public init(from: From.Type, _ label: String) {
        self.fromType = from
        self.forwardLabel = label
    }

    public func hasOne() -> TypedLinkBuilder {
        var copy = self
        copy.forwardCardinality = .one
        return copy
    }

    public func hasMany() -> TypedLinkBuilder {
        var copy = self
        copy.forwardCardinality = .many
        return copy
    }

    public func required() -> TypedLinkBuilder {
        var copy = self
        copy.forwardRequired = true
        return copy
    }

    public func onDeleteCascade() -> TypedLinkBuilder {
        var copy = self
        copy.forwardOnDelete = .cascade
        return copy
    }

    public func to(_ toType: To.Type, _ label: String) -> TypedLinkBuilder {
        var copy = self
        copy.toType = toType
        copy.reverseLabel = label
        return copy
    }

    public func reverseHasOne() -> TypedLinkBuilder {
        var copy = self
        copy.reverseCardinality = .one
        return copy
    }

    public func reverseHasMany() -> TypedLinkBuilder {
        var copy = self
        copy.reverseCardinality = .many
        return copy
    }

    public func reverseOnDeleteCascade() -> TypedLinkBuilder {
        var copy = self
        copy.reverseOnDelete = .cascade
        return copy
    }

    public func build() -> SchemaLink? {
        guard toType != nil, let reverseLabel else { return nil }

        var forward = LinkEndpoint(
            on: From.namespace,
            label: forwardLabel,
            has: forwardCardinality
        )
        forward.isRequired = forwardRequired
        forward.onDelete = forwardOnDelete

        var reverse = LinkEndpoint(
            on: To.namespace,
            label: reverseLabel,
            has: reverseCardinality
        )
        reverse.onDelete = reverseOnDelete

        return SchemaLink(forward: forward, reverse: reverse)
    }
}

public func Link<From: InstantEntitySchema, To: InstantEntitySchema>(
    from: From.Type,
    _ label: String
) -> TypedLinkBuilder<From, To> {
    TypedLinkBuilder(from: from, label)
}

public func Entity<E: InstantEntitySchema>(
    _ type: E.Type,
    @TypedAttributeBuilder configs: () -> [TypedAttributeConfig] = { [] }
) -> TypedEntity<E> {
    TypedEntity(type, configs: configs)
}
