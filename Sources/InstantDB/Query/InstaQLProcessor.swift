import Foundation

/// Processes datalog results from InstantDB into InstaQL format with support for linked entities.
///
/// ## How Links Work
///
/// When a query includes linked entities (e.g., `posts.with(\.author)`), the server returns
/// triples for both the parent entities and the linked entities. The processor:
///
/// 1. Collects all triples and groups them by entity ID and namespace
/// 2. Identifies `ref` type attributes (links) by checking `valueType == .ref`
/// 3. For each link, creates BOTH forward and reverse relationships
///
/// ## Link Direction
///
/// InstantDB links are bidirectional. A link attribute has:
/// - `forwardIdentity`: `["attrId", "profiles", "posts"]` - Profile has many Posts
/// - `reverseIdentity`: `["attrId", "posts", "author"]` - Post has one Author (Profile)
///
/// When we see a triple `[profileId, linkAttrId, postId]`:
/// - Forward: `profiles[profileId].posts = [postId, ...]` (one-to-many)
/// - Reverse: `posts[postId].author = profileId` (many-to-one)
///
/// ## Example
///
/// Query: `{ posts: { author: {} } }`
///
/// Server returns triples like:
/// ```
/// [postId, contentAttrId, "Hello world"]
/// [profileId, postsLinkAttrId, postId]  // This is a ref! Creates BOTH directions
/// [profileId, nameAttrId, "Alice"]
/// ```
///
/// Result:
/// ```json
/// {
///   "posts": [{
///     "id": "postId",
///     "content": "Hello world",
///     "author": {
///       "id": "profileId",
///       "name": "Alice"
///     }
///   }]
/// }
/// ```
/// Specifies how to order query results
struct QueryOrder {
  let field: String
  let direction: OrderDirection
  
  enum OrderDirection {
    case asc
    case desc
  }
}

struct InstaQLProcessor {
  
  /// Process datalog-result into InstaQL format
  /// - Parameters:
  ///   - result: Raw result array from server
  ///   - attributes: Schema attributes
  ///   - order: Optional ordering to apply (client-side sort)
  /// - Returns: Processed InstaQL data
  static func process(
    result: [[String: Any]],
    attributes: [Attribute],
    order: QueryOrder? = nil
  ) -> [String: Any] {
    var triples: [[Any]] = []
    for item in result {
      guard let data = item["data"] as? [String: Any],
            let datalogResult = data["datalog-result"] as? [String: Any],
            let joinRows = datalogResult["join-rows"] as? [[[Any]]] else {
        continue
      }
      
      for rows in joinRows {
        for triple in rows {
          triples.append(triple)
        }
      }
    }
    
    // Build attribute lookup by ID for fast access
    let attrById: [String: Attribute] = Dictionary(
      uniqueKeysWithValues: attributes.map { ($0.id, $0) }
    )
    
    // First pass: collect all entities by namespace and ID
    // Also track ref attributes for second pass
    var entities: [String: [String: [String: Any]]] = [:]
    // namespace -> entityId -> attributes
    
    // Track ref relationships for BOTH directions
    // Forward: (parentNamespace, parentId, linkLabel, linkedId, linkedNamespace)
    // Reverse: (childNamespace, childId, reverseLinkLabel, parentId, parentNamespace)
    struct RefLink {
      let parentNamespace: String
      let parentId: String
      let linkLabel: String
      let linkedId: String
      let linkedNamespace: String
      let cardinality: Cardinality?
    }

    struct RefEdge {
      let sourceNamespace: String
      let sourceId: String
      let attrName: String
      let attributeId: String
      let linkedId: String
      let cardinality: Cardinality?
      let reverseIdentity: [String]?
    }
    
    var forwardLinks: [RefLink] = []
    var reverseLinks: [RefLink] = []
    var refEdges: [RefEdge] = []
    
    for triple in triples {
      guard triple.count >= 3,
            let entityId = triple[0] as? String,
            let attrId = triple[1] as? String else {
        continue
      }
      
      let value = triple[2]
      
      guard let attr = attrById[attrId] else {
        InstantLog.warningOnce(
          "instaql.missing-attr-id.\(attrId)",
          "[InstaQLProcessor] Warning: Attribute ID '\(attrId)' not found in schema. Dropping triple for entity '\(entityId)'."
        )
        continue
      }
      
      let namespace = attr.forwardIdentity[1]
      let attrName = attr.forwardIdentity[2]
      
      // Skip 'id' attribute (it's the entity ID itself)
      if attrName == "id" {
        continue
      }
      
      // Initialize namespace if needed
      if entities[namespace] == nil {
        entities[namespace] = [:]
      }
      
      // Initialize entity if needed
      if entities[namespace]?[entityId] == nil {
        entities[namespace]?[entityId] = ["id": entityId]
      }
      
      // Handle ref attributes (links) specially
      if attr.valueType == .ref {
        // The value is the ID of the linked entity
        if let linkedId = value as? String {
          refEdges.append(
            RefEdge(
              sourceNamespace: namespace,
              sourceId: entityId,
              attrName: attrName,
              attributeId: attrId,
              linkedId: linkedId,
              cardinality: attr.cardinality,
              reverseIdentity: attr.reverseIdentity
            )
          )
        }
      } else {
        // Regular attribute - add directly to entity
        entities[namespace]?[entityId]?[attrName] = value
      }
    }

    var namespaceByEntityId: [String: String] = [:]
    for (namespace, entitiesById) in entities {
      for entityId in entitiesById.keys {
        namespaceByEntityId[entityId] = namespace
      }
    }

    for edge in refEdges {
      let linkedNamespace: String?
      let reverseLabel: String?

      if let reverseIdentity = edge.reverseIdentity, reverseIdentity.count >= 3 {
        linkedNamespace = reverseIdentity[1]
        reverseLabel = reverseIdentity[2]
      } else {
        linkedNamespace = namespaceByEntityId[edge.linkedId]
        reverseLabel = nil

        InstantLog.warningOnce(
          "instaql.missing-reverse-identity.\(edge.attributeId)",
          """
          [InstaQLProcessor] Warning: Missing reverse identity for link '\(edge.sourceNamespace).\(edge.attrName)' (attribute: \(edge.attributeId)).

          WHAT HAPPENED:
            The server schema did not include `reverse-identity` metadata for this ref attribute.

          WHY THIS MATTERS:
            The client uses reverse identities to infer the linked namespace and to construct reverse links.

          WHAT WE DID:
            We inferred the linked namespace from the query result payload and nested the linked entity.
            Reverse links are not inferred without schema metadata.
          """
        )
      }

      guard let linkedNamespace else {
        InstantLog.warningOnce(
          "instaql.missing-linked-namespace.\(edge.attributeId)",
          """
          [InstaQLProcessor] Warning: Unable to infer linked namespace for link '\(edge.sourceNamespace).\(edge.attrName)' (attribute: \(edge.attributeId)).

          HOW TO FIX:
            Ensure the schema attribute includes a `reverse-identity` or that the linked entity is included in the query result.
          """
        )
        continue
      }

      forwardLinks.append(
        RefLink(
          parentNamespace: edge.sourceNamespace,
          parentId: edge.sourceId,
          linkLabel: edge.attrName,
          linkedId: edge.linkedId,
          linkedNamespace: linkedNamespace,
          cardinality: edge.cardinality
        )
      )

      if let reverseLabel {
        reverseLinks.append(
          RefLink(
            parentNamespace: linkedNamespace,
            parentId: edge.linkedId,
            linkLabel: reverseLabel,
            linkedId: edge.sourceId,
            linkedNamespace: edge.sourceNamespace,
            cardinality: nil
          )
        )
      }
    }
    
    // Second pass: resolve forward links by nesting linked entities
    // We create shallow copies to avoid circular references
    for link in forwardLinks {
      // Look up the linked entity
      if let linkedEntity = entities[link.linkedNamespace]?[link.linkedId] {
        // Create a shallow copy without link properties to avoid circular references
        let shallowEntity = createShallowCopy(linkedEntity, excludingLinks: true)
        
        // Check if this is a has-one or has-many relationship
        if let existingValue = entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] {
          // Already has a value - this is a has-many, append to array
          if var existingArray = existingValue as? [[String: Any]] {
            existingArray.append(shallowEntity)
            entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = existingArray
          } else if let existingSingle = existingValue as? [String: Any] {
            // Convert single to array
            entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = [existingSingle, shallowEntity]
          }
        } else {
          // First value
          if link.cardinality == .many {
             // Explicitly create array for has-many, even if single item
             entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = [shallowEntity]
          } else {
             // Store as single entity (has-one)
             entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = shallowEntity
          }
        }
      } else {
          // [InstaQL] Info: Linked entity not found in result set.
          // This is common if the linked entity wasn't loaded in the query.
          // keeping this silent to avoid noise as it's often expected behavior.
      }
    }
    
    // Third pass: resolve reverse links by nesting linked entities
    // This handles cases like posts.author where the link is stored on profiles
    for link in reverseLinks {
      // Look up the linked entity (the parent in reverse direction)
      if let linkedEntity = entities[link.linkedNamespace]?[link.linkedId] {
        // Create a shallow copy without link properties to avoid circular references
        let shallowEntity = createShallowCopy(linkedEntity, excludingLinks: true)
        
        // Ensure the child entity exists
        if entities[link.parentNamespace]?[link.parentId] != nil {
          // Check if this is a has-one or has-many relationship
          if let existingValue = entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] {
            // Already has a value - this is a has-many, append to array
            if var existingArray = existingValue as? [[String: Any]] {
              existingArray.append(shallowEntity)
              entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = existingArray
            } else if let existingSingle = existingValue as? [String: Any] {
              // Convert single to array
              entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = [existingSingle, shallowEntity]
            }
          } else {
            // First value - store as single entity (has-one for reverse links typically)
            entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = shallowEntity
          }
        }
      }
    }
    
    // Convert to InstaQL format: {namespace: [entity1, entity2, ...]}
    // Apply client-side sorting if order is specified (like TypeScript client does)
    var instaqlData: [String: Any] = [:]
    for (namespace, entitiesById) in entities {
      var entityArray = Array(entitiesById.values)
      
      // Apply client-side sorting if order is specified
      // This matches the TypeScript client behavior in instaql.ts lines 723-730
      if let order = order {
        entityArray.sort { a, b in
          let aValue = a[order.field]
          let bValue = b[order.field]
          
          // Handle comparison based on value types
          let comparison: Int
          if let aNum = aValue as? Double, let bNum = bValue as? Double {
            comparison = aNum < bNum ? -1 : (aNum > bNum ? 1 : 0)
          } else if let aStr = aValue as? String, let bStr = bValue as? String {
            comparison = aStr.compare(bStr).rawValue
          } else if let aInt = aValue as? Int, let bInt = bValue as? Int {
            comparison = aInt < bInt ? -1 : (aInt > bInt ? 1 : 0)
          } else {
            // Fallback: compare string representations
            let aDesc = String(describing: aValue ?? "")
            let bDesc = String(describing: bValue ?? "")
            comparison = aDesc.compare(bDesc).rawValue
          }
          
          // Apply direction
          return order.direction == .asc ? comparison < 0 : comparison > 0
        }
      }
      
      instaqlData[namespace] = entityArray
    }
    
    return instaqlData
  }
  
  /// Creates a shallow copy of an entity dictionary, optionally excluding nested link properties.
  ///
  /// This is used when nesting linked entities to avoid circular references.
  /// For example, when nesting a Profile under Post.author, we don't want the Profile
  /// to include its own `posts` array (which would contain the Post we're building).
  ///
  /// - Parameters:
  ///   - entity: The entity dictionary to copy
  ///   - excludingLinks: If true, excludes properties that are dictionaries or arrays of dictionaries
  /// - Returns: A shallow copy of the entity
  private static func createShallowCopy(_ entity: [String: Any], excludingLinks: Bool) -> [String: Any] {
    guard excludingLinks else { return entity }
    
    var copy: [String: Any] = [:]
    for (key, value) in entity {
      // Skip nested entities (links) - they're dictionaries or arrays of dictionaries
      if value is [String: Any] || value is [[String: Any]] {
        continue
      }
      copy[key] = value
    }
    return copy
  }
}
