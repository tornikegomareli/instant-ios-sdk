import Foundation

public protocol InstantEntitySchema {
    static var namespace: String { get }
    static var schemaAttributes: [SchemaAttributeInfo] { get }
}

public struct SchemaAttributeInfo: Sendable {
    public let name: String
    public let dataType: InstantDataType
    public let isOptional: Bool

    public init(name: String, dataType: InstantDataType, isOptional: Bool = false) {
        self.name = name
        self.dataType = dataType
        self.isOptional = isOptional
    }
}

public enum SwiftTypeMapper {
    public static func mapType(_ swiftType: Any.Type) -> InstantDataType {
        switch swiftType {
        case is String.Type, is String?.Type:
            return .string
        case is Int.Type, is Int?.Type,
             is Double.Type, is Double?.Type,
             is Float.Type, is Float?.Type:
            return .number
        case is Bool.Type, is Bool?.Type:
            return .boolean
        case is Date.Type, is Date?.Type:
            return .date
        default:
            return .json
        }
    }
}
