import Foundation

enum SchemaPrinter {
  static func print(_ schema: [String: Any]) {
    if let entities = schema["entities"] as? [String: Any] {
      Swift.print("\nEntities:")
      for (name, attrs) in entities.sorted(by: { $0.key < $1.key }) {
        Swift.print("  \(name):")
        if let attributes = attrs as? [String: Any] {
          for (attrName, attrConfig) in attributes.sorted(by: { $0.key < $1.key }) {
            if let config = attrConfig as? [String: Any] {
              var flags: [String] = []
              if let type = config["valueType"] as? String { flags.append(type) }
              if config["indexed"] as? Bool == true { flags.append("indexed") }
              if config["unique"] as? Bool == true { flags.append("unique") }
              if config["optional"] as? Bool == true { flags.append("optional") }
              Swift.print("    \(attrName): \(flags.joined(separator: ", "))")
            }
          }
        }
      }
    }

    if let links = schema["links"] as? [String: Any], !links.isEmpty {
      Swift.print("\nLinks:")
      for (name, linkConfig) in links.sorted(by: { $0.key < $1.key }) {
        if let config = linkConfig as? [String: Any],
           let forward = config["forward"] as? [String: Any],
           let reverse = config["reverse"] as? [String: Any] {
          let fwdEntity = forward["on"] as? String ?? "?"
          let fwdLabel = forward["label"] as? String ?? "?"
          let fwdCardinality = forward["has"] as? String ?? "?"
          let revEntity = reverse["on"] as? String ?? "?"
          let revLabel = reverse["label"] as? String ?? "?"
          let revCardinality = reverse["has"] as? String ?? "?"
          Swift.print("  \(name):")
          Swift.print("    \(fwdEntity).\(fwdLabel) has \(fwdCardinality) <-> \(revEntity).\(revLabel) has \(revCardinality)")
        }
      }
    }
  }
}
