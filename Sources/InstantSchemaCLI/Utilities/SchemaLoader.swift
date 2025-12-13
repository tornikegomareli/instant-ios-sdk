import Foundation
import InstantDB

enum SchemaLoader {
  static func load(from path: String) throws -> InstantSchema {
    guard FileManager.default.fileExists(atPath: path) else {
      throw CLIError.fileNotFound(path)
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try loadFromData(data)
  }

  static func loadFromData(_ data: Data) throws -> InstantSchema {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CLIError.invalidJSON
    }

    return try parse(json)
  }

  private static func parse(_ json: [String: Any]) throws -> InstantSchema {
    var entities: [SchemaEntity] = []
    var links: [SchemaLink] = []

    if let entitiesDict = json["entities"] as? [String: [String: Any]] {
      for (name, entityConfig) in entitiesDict {
        if let attrs = entityConfig["attrs"] as? [String: [String: Any]] {
          let entity = parseEntity(name: name, attributes: attrs)
          entities.append(entity)
        }
      }
    }

    if let linksDict = json["links"] as? [String: [String: [String: Any]]] {
      for (_, config) in linksDict {
        if let link = parseLink(config) {
          links.append(link)
        }
      }
    }

    return InstantSchema(entities: entities, links: links)
  }

  private static func parseEntity(name: String, attributes: [String: [String: Any]]) -> SchemaEntity {
    var parsedAttrs: [SchemaAttribute] = []

    for (attrName, attrConfig) in attributes {
      let type = InstantDataType(rawValue: attrConfig["valueType"] as? String ?? "any") ?? .any
      var attr = Attr(attrName, type)

      let config = attrConfig["config"] as? [String: Any] ?? [:]
      if config["indexed"] as? Bool == true { attr = attr.indexed() }
      if config["unique"] as? Bool == true { attr = attr.unique() }
      if attrConfig["required"] as? Bool != true { attr = attr.optional() }

      parsedAttrs.append(attr)
    }

    return SchemaEntity(name, attributes: parsedAttrs)
  }

  private static func parseLink(_ config: [String: [String: Any]]) -> SchemaLink? {
    guard let fwd = config["forward"],
          let rev = config["reverse"],
          let fwdOn = fwd["on"] as? String,
          let fwdLabel = fwd["label"] as? String,
          let revOn = rev["on"] as? String,
          let revLabel = rev["label"] as? String else {
      return nil
    }

    let forward = LinkEndpoint(
      on: fwdOn,
      label: fwdLabel,
      has: InstantDB.Cardinality(rawValue: fwd["has"] as? String ?? "one") ?? .one
    )

    let reverse = LinkEndpoint(
      on: revOn,
      label: revLabel,
      has: InstantDB.Cardinality(rawValue: rev["has"] as? String ?? "many") ?? .many
    )

    return SchemaLink(forward: forward, reverse: reverse)
  }
}
