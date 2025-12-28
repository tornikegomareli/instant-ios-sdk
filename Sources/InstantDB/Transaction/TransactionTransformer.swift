import Foundation

/// Transforms high-level transaction operations into low-level tx-steps format
final class TransactionTransformer {

  private struct TempAttribute {
    let id: String
    let forwardIdentity: [String]
    let reverseIdentity: [String]?
    let valueType: String
    let cardinality: String
    let unique: Bool
    let indexed: Bool
  }
  
  /// Result of looking up an attribute, including whether it was found via reverse identity
  private struct AttributeLookupResult {
    let attrId: String
    let isReverse: Bool
  }

  /// Convert transaction chunks into tx-steps format for the server
  /// - Parameters:
  ///   - chunks: Transaction chunks to transform
  ///   - attributes: Schema attributes from the server
  /// - Returns: Tuple of (tx-steps, new attributes to add to local schema)
  static func transform(_ chunks: [TransactionChunk], attributes: [Attribute]) throws -> (txSteps: [[Any]], newAttributes: [Attribute]) {
    var addAttrSteps: [[Any]] = []
    var dataSteps: [[Any]] = []
    var tempAttrs: [String: TempAttribute] = [:]
    var newAttributes: [Attribute] = []

    // Helper to get or create attribute (returns just the ID for non-link operations)
    func getOrCreateAttr(entityType: String, label: String) -> String {
      return getOrCreateAttrWithDirection(entityType: entityType, label: label, isMany: false, linkedNamespace: nil, valueType: "blob").attrId
    }
    
    // Helper to get or create attribute with direction info (for link operations)
    func getOrCreateAttrWithDirection(entityType: String, label: String, isMany: Bool = false, linkedNamespace: String? = nil, valueType: String = "blob") -> AttributeLookupResult {
      let key = "\(entityType).\(label)"

      // Check if attribute exists in schema (forward identity first)
      if let fwdAttr = findAttributeByForwardIdentity(entityType: entityType, label: label, attributes: attributes) {
        
        
        // REPAIR LOGIC: If we found an attribute, but it's a broken link (missing reverseIdentity),
        // and we have the info to fix it (linkedNamespace), we should issue an update-attr op.

        // Check if repair is needed:
        // 1. We want a reference (valueType == "ref")
        // 2. We have the necessary info (linkedNamespace)
        // 3. The existing attribute is either:
        //    a. A 'blob' (incorrect type for a link)
        //    b. A 'ref' but missing reverseIdentity (broken link)
        let isBrokenLink = (fwdAttr.valueType == .ref && (fwdAttr.reverseIdentity == nil || fwdAttr.reverseIdentity?.count ?? 0 < 3))
        let isIncorrectType = (fwdAttr.valueType == .blob && valueType == "ref")
	        
	        if let linkedNs = linkedNamespace, (isBrokenLink || isIncorrectType) {

	             // Check if we've already scheduled a repair for this attribute
	             if tempAttrs[key] == nil {
	               let reason = isIncorrectType ? "Incorrect type (blob -> ref)" : "Missing reverse identity"
	               InstantLog.debug("[TransactionTransformer] Repairing schema for '\(key)': \(reason)")
	               
	               let revIdentId = UUID().uuidString.lowercased()
	               let reverseIdentity = [revIdentId, linkedNs, entityType]
               
               // Use the existing attribute ID so the server treats this as an update.
               let tempAttr = TempAttribute(
                 id: fwdAttr.id,
                 forwardIdentity: fwdAttr.forwardIdentity,
                 reverseIdentity: reverseIdentity,
                 valueType: "ref",
                 cardinality: fwdAttr.cardinality == .many ? "many" : "one",
                 unique: fwdAttr.unique ?? false,
                 indexed: fwdAttr.indexed ?? false
               )
               tempAttrs[key] = tempAttr
               
               // Generate update-attr op (same as add-attr but with existing ID)
               // Build dictionary without nil values
               var updateAttrDict: [String: Any] = [
                 "id": fwdAttr.id,
                 "forward-identity": tempAttr.forwardIdentity,
                 "value-type": tempAttr.valueType,
                 "cardinality": tempAttr.cardinality,
                 "unique?": tempAttr.unique,
                 "index?": tempAttr.indexed,
                 "isUnsynced": true
               ]
               if let revIdent = tempAttr.reverseIdentity {
                 updateAttrDict["reverse-identity"] = revIdent
               }
               let updateAttrOp: [Any] = ["add-attr", updateAttrDict]
               addAttrSteps.append(updateAttrOp)

               let repairedAttr = Attribute(
                 id: fwdAttr.id,
                 forwardIdentity: tempAttr.forwardIdentity,
                 reverseIdentity: tempAttr.reverseIdentity,
                 valueType: .ref,
                 cardinality: fwdAttr.cardinality,
                 unique: tempAttr.unique,
                 indexed: tempAttr.indexed,
                 checkedDataType: fwdAttr.checkedDataType
               )
               newAttributes.append(repairedAttr)
             }
        }
        
        return AttributeLookupResult(attrId: fwdAttr.id, isReverse: false)
      }
      
      // Check reverse identity (for link attributes)
      if let revAttr = findAttributeByReverseIdentity(entityType: entityType, label: label, attributes: attributes) {
        return AttributeLookupResult(attrId: revAttr.id, isReverse: true)
      }

      // Repair case: We are linking from the reverse side, but the server schema is
      // missing `reverse-identity`, so we cannot find the attr by reverse identity.
      //
      // Example (Microblog):
      // - Schema has `profiles.posts` as the forward identity.
      // - We call `posts.link({author: profileId})`.
      // - If the reverse identity (`posts.author`) is missing, we still want to find
      //   `profiles.posts` and repair it using the reverse label we are invoking (`author`).
      if let linkedNs = linkedNamespace,
         let mirroredForwardAttr = findAttributeByForwardIdentity(entityType: linkedNs, label: entityType, attributes: attributes) {
        let mirroredKey = "\(linkedNs).\(entityType)"
        let wantsRef = (valueType == "ref")

        let isBrokenLink = (mirroredForwardAttr.valueType == .ref && (mirroredForwardAttr.reverseIdentity == nil || mirroredForwardAttr.reverseIdentity?.count ?? 0 < 3))
        let isIncorrectType = (mirroredForwardAttr.valueType == .blob && wantsRef)

        if wantsRef, (isBrokenLink || isIncorrectType), tempAttrs[mirroredKey] == nil {
          let reason = isIncorrectType ? "Incorrect type (blob -> ref)" : "Missing reverse identity"
          InstantLog.debug("[TransactionTransformer] Repairing schema for '\(linkedNs).\(entityType)' via reverse label '\(label)': \(reason)")

          let revIdentId = UUID().uuidString.lowercased()
          let reverseIdentity = [revIdentId, entityType, label]

          let tempAttr = TempAttribute(
            id: mirroredForwardAttr.id,
            forwardIdentity: mirroredForwardAttr.forwardIdentity,
            reverseIdentity: reverseIdentity,
            valueType: "ref",
            cardinality: mirroredForwardAttr.cardinality == .many ? "many" : "one",
            unique: mirroredForwardAttr.unique ?? false,
            indexed: mirroredForwardAttr.indexed ?? false
          )
          tempAttrs[mirroredKey] = tempAttr

          // Build dictionary without nil values
          var mirroredAttrDict: [String: Any] = [
            "id": mirroredForwardAttr.id,
            "forward-identity": tempAttr.forwardIdentity,
            "value-type": tempAttr.valueType,
            "cardinality": tempAttr.cardinality,
            "unique?": tempAttr.unique,
            "index?": tempAttr.indexed,
            "isUnsynced": true
          ]
          if let revIdent = tempAttr.reverseIdentity {
            mirroredAttrDict["reverse-identity"] = revIdent
          }
          let updateAttrOp: [Any] = ["add-attr", mirroredAttrDict]
          addAttrSteps.append(updateAttrOp)

          let repairedAttr = Attribute(
            id: mirroredForwardAttr.id,
            forwardIdentity: tempAttr.forwardIdentity,
            reverseIdentity: tempAttr.reverseIdentity,
            valueType: .ref,
            cardinality: mirroredForwardAttr.cardinality,
            unique: tempAttr.unique,
            indexed: tempAttr.indexed,
            checkedDataType: mirroredForwardAttr.checkedDataType
          )
          newAttributes.append(repairedAttr)
        }

        return AttributeLookupResult(attrId: mirroredForwardAttr.id, isReverse: true)
      }

      // Check if we already created a temp attribute
      if let tempAttr = tempAttrs[key] {
        return AttributeLookupResult(attrId: tempAttr.id, isReverse: false)
      }

      // Create new temp attribute (lowercase to match server format)
      let attrId = UUID().uuidString.lowercased()
      let fwdIdentId = UUID().uuidString.lowercased()
      
      // If we know the linked namespace, we can create a reverse identity
      var reverseIdentity: [String]? = nil
      if let linkedNs = linkedNamespace {
          let revIdentId = UUID().uuidString.lowercased()
          // Construct reverse identity: [id, destination_namespace, reverse_label]
          // Note: We use the same label for reverse direction if simplistic, or ideally we'd infer it.
          // For now, we'll assume the reverse label is the source entity type (e.g. "posts" for author link)
          // or we can just use the label. 
          // InstantDB typically uses explicit reverse labels.
          // Using the entityType as the reverse label is a reasonable default for dynamic schema.
          reverseIdentity = [revIdentId, linkedNs, entityType]
      }
      
      let tempAttr = TempAttribute(
        id: attrId,
        forwardIdentity: [fwdIdentId, entityType, label],
        reverseIdentity: reverseIdentity,
        valueType: valueType,
        cardinality: isMany ? "many" : "one",
        unique: label == "id",
        indexed: false
      )
      tempAttrs[key] = tempAttr

      // Create add-attr operation
      // Build the attribute dictionary, only including reverse-identity if it exists
      var attrDict: [String: Any] = [
        "id": attrId,
        "forward-identity": tempAttr.forwardIdentity,
        "value-type": tempAttr.valueType,
        "cardinality": tempAttr.cardinality,
        "unique?": tempAttr.unique,
        "index?": tempAttr.indexed,
        "isUnsynced": true
      ]
      if let revIdent = tempAttr.reverseIdentity {
        attrDict["reverse-identity"] = revIdent
      }
      
      let addAttrOp: [Any] = ["add-attr", attrDict]
      addAttrSteps.append(addAttrOp)

      // Also create an Attribute object for local schema
      let newAttr = Attribute(
        id: attrId,
        forwardIdentity: tempAttr.forwardIdentity,
        reverseIdentity: tempAttr.reverseIdentity,
        valueType: valueType == "ref" ? .ref : .blob,
        cardinality: isMany ? .many : .one,
        unique: tempAttr.unique,
        indexed: tempAttr.indexed,
        checkedDataType: nil
      )
      newAttributes.append(newAttr)

      return AttributeLookupResult(attrId: attrId, isReverse: false)
    }

    // Process all operations
    for chunk in chunks {
      for op in chunk.ops {
        let steps = try transformOperation(op, getOrCreateAttr: getOrCreateAttr, getOrCreateAttrWithDirection: getOrCreateAttrWithDirection)
        dataSteps.append(contentsOf: steps)
      }
    }

    // Return add-attr operations first, then data operations, plus new attributes
    return (txSteps: addAttrSteps + dataSteps, newAttributes: newAttributes)
  }

  private static func transformOperation(
    _ op: [Any],
    getOrCreateAttr: (String, String) -> String,
    getOrCreateAttrWithDirection: (String, String, Bool, String?, String) -> AttributeLookupResult
  ) throws -> [[Any]] {
    guard op.count >= 3,
          let action = op[0] as? String,
          let entityType = op[1] as? String,
          let entityId = op[2] as? String else {
      throw InstantError.invalidQuery
    }

    switch action {
    case "create":
      return try expandCreate(entityType: entityType, entityId: entityId, data: op[3], getOrCreateAttr: getOrCreateAttr)

    case "update":
      return try expandUpdate(entityType: entityType, entityId: entityId, data: op[3], opts: op.count > 4 ? op[4] : nil, getOrCreateAttr: getOrCreateAttr)

    case "merge":
      return try expandMerge(entityType: entityType, entityId: entityId, data: op[3], opts: op.count > 4 ? op[4] : nil, getOrCreateAttr: getOrCreateAttr)

    case "link":
      return try expandLink(entityType: entityType, entityId: entityId, links: op[3], getOrCreateAttrWithDirection: getOrCreateAttrWithDirection)

    case "unlink":
      return try expandUnlink(entityType: entityType, entityId: entityId, links: op[3], getOrCreateAttrWithDirection: getOrCreateAttrWithDirection)

    case "delete":
      return [["delete-entity", entityId, entityType]]

    default:
      throw InstantError.invalidQuery
    }
  }

  private static func expandCreate(entityType: String, entityId: String, data: Any?, getOrCreateAttr: (String, String) -> String) throws -> [[Any]] {
    guard let dataDict = data as? [String: Any] else {
      throw InstantError.invalidQuery
    }

    var steps: [[Any]] = []

    // Add id triple first
    let idAttrId = getOrCreateAttr(entityType, "id")
    steps.append(["add-triple", entityId, idAttrId, entityId, ["mode": "create"]])

    // Add data triples
    for (key, value) in dataDict {
      let attrId = getOrCreateAttr(entityType, key)
      steps.append(["add-triple", entityId, attrId, value, ["mode": "create"]])
    }

    return steps
  }

  private static func expandUpdate(entityType: String, entityId: String, data: Any?, opts: Any?, getOrCreateAttr: (String, String) -> String) throws -> [[Any]] {
    guard let dataDict = data as? [String: Any] else {
      throw InstantError.invalidQuery
    }

    var steps: [[Any]] = []

    // Add id triple first
    let idAttrId = getOrCreateAttr(entityType, "id")
    if let optsDict = opts as? [String: Any] {
      steps.append(["add-triple", entityId, idAttrId, entityId, optsDict])
    } else {
      steps.append(["add-triple", entityId, idAttrId, entityId])
    }

    // Add data triples
    for (key, value) in dataDict {
      let attrId = getOrCreateAttr(entityType, key)
      if let optsDict = opts as? [String: Any] {
        steps.append(["add-triple", entityId, attrId, value, optsDict])
      } else {
        steps.append(["add-triple", entityId, attrId, value])
      }
    }

    return steps
  }

  private static func expandMerge(entityType: String, entityId: String, data: Any?, opts: Any?, getOrCreateAttr: (String, String) -> String) throws -> [[Any]] {
    guard let dataDict = data as? [String: Any] else {
      throw InstantError.invalidQuery
    }

    var steps: [[Any]] = []

    // Add id triple first
    let idAttrId = getOrCreateAttr(entityType, "id")
    if let optsDict = opts as? [String: Any] {
      steps.append(["add-triple", entityId, idAttrId, entityId, optsDict])
    } else {
      steps.append(["add-triple", entityId, idAttrId, entityId])
    }

    // Add deep-merge-triple for each attribute
    for (key, value) in dataDict {
      let attrId = getOrCreateAttr(entityType, key)
      if let optsDict = opts as? [String: Any] {
        steps.append(["deep-merge-triple", entityId, attrId, value, optsDict])
      } else {
        steps.append(["deep-merge-triple", entityId, attrId, value])
      }
    }

    return steps
  }

  /// Expand link operation into add-triple steps
  ///
  /// ## Why This Handles Forward vs Reverse Links
  ///
  /// In InstantDB, links have two sides defined in the schema:
  /// - Forward: e.g., `profiles.posts` (Profile has many Posts)
  /// - Reverse: e.g., `posts.author` (Post has one Profile)
  ///
  /// When we do `posts.link({author: profileId})`, we're using the reverse side.
  /// The attribute is stored as `profiles.posts` with a reverse identity of `posts.author`.
  ///
  /// The server expects the triple to be: `[profileId, linkAttrId, postId]` (forward direction)
  /// But we're calling from the post side: `posts[postId].link({author: profileId})`
  ///
  /// So when we find the attribute via reverse identity, we need to swap the IDs:
  /// - Forward: `["add-triple", entityId, attrId, linkedId]`
  /// - Reverse: `["add-triple", linkedId, attrId, entityId]`
  /// Expand link operation into add-triple steps
  ///
  /// ## Why This Handles Forward vs Reverse Links
  ///
  /// In InstantDB, links have two sides defined in the schema:
  /// - Forward: e.g., `profiles.posts` (Profile has many Posts)
  /// - Reverse: e.g., `posts.author` (Post has one Profile)
  ///
  /// When we do `posts.link({author: profileId})`, we're using the reverse side.
  /// The attribute is stored as `profiles.posts` with a reverse identity of `posts.author`.
  ///
  /// The server expects the triple to be: `[profileId, linkAttrId, postId]` (forward direction)
  /// But we're calling from the post side: `posts[postId].link({author: profileId})`
  ///
  /// So when we find the attribute via reverse identity, we need to swap the IDs:
  /// - Forward: `["add-triple", entityId, attrId, linkedId]`
  /// - Reverse: `["add-triple", linkedId, attrId, entityId]`
  private static func expandLink(
    entityType: String,
    entityId: String,
    links: Any?,
    getOrCreateAttrWithDirection: (String, String, Bool, String?, String) -> AttributeLookupResult
  ) throws -> [[Any]] {
    guard let linksDict = links as? [String: Any] else {
      throw InstantError.invalidQuery
    }

    var steps: [[Any]] = []

    for (linkName, linkValue) in linksDict {
      // Handle both single ID, array of IDs, and namespaced dictionaries
      let linkIds: [String]
      let isMany: Bool
      var linkedNamespace: String? = nil
      
      if let singleId = linkValue as? String {
        linkIds = [singleId]
        isMany = false
      } else if let multipleIds = linkValue as? [String] {
        linkIds = multipleIds
        isMany = true
      } else if let dict = linkValue as? [String: String],
                let id = dict["id"],
                let ns = dict["namespace"] {
        linkIds = [id]
        linkedNamespace = ns
        isMany = false
      } else if let dictArray = linkValue as? [[String: String]] {
        linkIds = dictArray.compactMap { $0["id"] }
        var ns: String? = nil
        // Assume consistent namespace for array
        if let first = dictArray.first {
            ns = first["namespace"]
        }
        linkedNamespace = ns
        isMany = true
      } else {
        continue
      }

      let lookupResult = getOrCreateAttrWithDirection(entityType, linkName, isMany, linkedNamespace, "ref")
      for linkedId in linkIds {
        if lookupResult.isReverse {
          // Reverse link: swap entity IDs
          // e.g., posts.author -> ["add-triple", profileId, attrId, postId]
          steps.append(["add-triple", linkedId, lookupResult.attrId, entityId])
        } else {
          // Forward link: normal order
          // e.g., profiles.posts -> ["add-triple", profileId, attrId, postId]
          steps.append(["add-triple", entityId, lookupResult.attrId, linkedId])
        }
      }
    }

    return steps
  }

  /// Expand unlink operation into retract-triple steps
  ///
  /// See `expandLink` for explanation of forward vs reverse link handling.
  private static func expandUnlink(
    entityType: String,
    entityId: String,
    links: Any?,
    getOrCreateAttrWithDirection: (String, String, Bool, String?, String) -> AttributeLookupResult
  ) throws -> [[Any]] {
    guard let linksDict = links as? [String: Any] else {
      throw InstantError.invalidQuery
    }

    var steps: [[Any]] = []

    for (linkName, linkValue) in linksDict {
      // Handle both single ID and array of IDs
      let linkIds: [String]
      let isMany: Bool
      
      if let singleId = linkValue as? String {
        linkIds = [singleId]
        isMany = false
      } else if let multipleIds = linkValue as? [String] {
        linkIds = multipleIds
        isMany = true
      } else {
        continue
      }

      let lookupResult = getOrCreateAttrWithDirection(entityType, linkName, isMany, nil, "ref")
      for linkedId in linkIds {
        if lookupResult.isReverse {
          // Reverse link: swap entity IDs
          steps.append(["retract-triple", linkedId, lookupResult.attrId, entityId])
        } else {
          // Forward link: normal order
          steps.append(["retract-triple", entityId, lookupResult.attrId, linkedId])
        }
      }
    }

    return steps
  }

  /// Find attribute by forward identity (entity type and label)
  private static func findAttributeByForwardIdentity(entityType: String, label: String, attributes: [Attribute]) -> Attribute? {
    return attributes.first { attr in
      attr.forwardIdentity.count >= 3 &&
      attr.forwardIdentity[1] == entityType &&
      attr.forwardIdentity[2] == label
    }
  }
  
  /// Find attribute by reverse identity (for link attributes accessed from the "other" side)
  private static func findAttributeByReverseIdentity(entityType: String, label: String, attributes: [Attribute]) -> Attribute? {
    return attributes.first { attr in
      guard let revIdent = attr.reverseIdentity, revIdent.count >= 3 else { return false }
      return revIdent[1] == entityType && revIdent[2] == label
    }
  }
}
