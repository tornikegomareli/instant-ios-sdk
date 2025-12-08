import Foundation

public struct SchemaSerializer {

  public static func toJSON(_ schema: InstantSchema) throws -> Data {
    let dict = toDictionary(schema)
    return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
  }

  public static func toJSONString(_ schema: InstantSchema) throws -> String {
    let data = try toJSON(schema)
    guard let string = String(data: data, encoding: .utf8) else {
      throw SchemaSerializerError.encodingFailed
    }
    return string
  }

  public static func toDictionary(_ schema: InstantSchema) -> [String: Any] {
    var entities: [String: Any] = [:]

    for entity in schema.entities {
      var attrs: [String: Any] = [:]
      for attr in entity.attributes {
        attrs[attr.name] = attributeToDictionary(attr)
      }
      entities[entity.name] = attrs
    }

    var links: [String: Any] = [:]
    for link in schema.links {
      links[link.name] = linkToDictionary(link)
    }

    return [
      "entities": entities,
      "links": links
    ]
  }

  private static func attributeToDictionary(_ attr: SchemaAttribute) -> [String: Any] {
    var dict: [String: Any] = [
      "valueType": attr.dataType.rawValue
    ]

    if attr.isIndexed {
      dict["indexed"] = true
    }

    if attr.isUnique {
      dict["unique"] = true
    }

    if attr.isOptional {
      dict["optional"] = true
    } else {
      dict["required"] = true
    }

    if attr.dataType != .any {
      dict["checkedDataType"] = attr.dataType.rawValue
    }

    return dict
  }

  private static func linkToDictionary(_ link: SchemaLink) -> [String: Any] {
    var forwardDict: [String: Any] = [
      "on": link.forward.entityName,
      "has": link.forward.cardinality.rawValue,
      "label": link.forward.label
    ]

    if link.forward.isRequired {
      forwardDict["required"] = true
    }

    if let onDelete = link.forward.onDelete {
      forwardDict["onDelete"] = onDelete.rawValue
    }

    var reverseDict: [String: Any] = [
      "on": link.reverse.entityName,
      "has": link.reverse.cardinality.rawValue,
      "label": link.reverse.label
    ]

    if let onDelete = link.reverse.onDelete {
      forwardDict["onDelete"] = onDelete.rawValue
    }

    return [
      "forward": forwardDict,
      "reverse": reverseDict
    ]
  }
}

public enum SchemaSerializerError: Error {
  case encodingFailed
}
