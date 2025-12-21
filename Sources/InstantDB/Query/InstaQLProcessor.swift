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
/// 3. For each link, looks up the linked entity and nests it under the parent
///
/// ## Example
///
/// Query: `{ posts: { author: {} } }`
///
/// Server returns triples like:
/// ```
/// [postId, contentAttrId, "Hello world"]
/// [postId, authorLinkAttrId, profileId]  // This is a ref!
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
struct InstaQLProcessor {
  
  /// Process datalog-result into InstaQL format
  /// - Parameters:
  ///   - result: Raw result array from server
  ///   - attributes: Schema attributes
  /// - Returns: Processed InstaQL data
  static func process(result: [[String: Any]], attributes: [Attribute]) -> [String: Any] {
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
    
    // Track ref relationships: (parentNamespace, parentId, linkLabel) -> linkedId
    var refLinks: [(parentNamespace: String, parentId: String, linkLabel: String, linkedId: String, linkedNamespace: String)] = []
    
    for triple in triples {
      guard triple.count >= 3,
            let entityId = triple[0] as? String,
            let attrId = triple[1] as? String else {
        continue
      }
      
      let value = triple[2]
      
      guard let attr = attrById[attrId] else {
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
        if let linkedId = value as? String,
           let reverseIdentity = attr.reverseIdentity,
           reverseIdentity.count >= 2 {
          // The reverse identity tells us the linked entity's namespace
          // reverseIdentity = [identId, linkedNamespace, reverseLabel]
          let linkedNamespace = reverseIdentity[1]
          
          // Store for second pass
          refLinks.append((
            parentNamespace: namespace,
            parentId: entityId,
            linkLabel: attrName,
            linkedId: linkedId,
            linkedNamespace: linkedNamespace
          ))
        }
      } else {
        // Regular attribute - add directly to entity
        entities[namespace]?[entityId]?[attrName] = value
      }
    }
    
    // Second pass: resolve ref links by nesting linked entities
    for link in refLinks {
      // Look up the linked entity
      if let linkedEntity = entities[link.linkedNamespace]?[link.linkedId] {
        // Check if this is a has-one or has-many relationship
        // For now, we'll check if there's already a value at this key
        if let existingValue = entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] {
          // Already has a value - this is a has-many, append to array
          if var existingArray = existingValue as? [[String: Any]] {
            existingArray.append(linkedEntity)
            entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = existingArray
          } else if let existingSingle = existingValue as? [String: Any] {
            // Convert single to array
            entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = [existingSingle, linkedEntity]
          }
        } else {
          // First value - store as single entity (has-one)
          // The TypeScript client uses cardinality inference to decide array vs single
          // For simplicity, we'll store as single and let the decoder handle it
          entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = linkedEntity
        }
      }
    }
    
    // Convert to InstaQL format: {namespace: [entity1, entity2, ...]}
    var instaqlData: [String: Any] = [:]
    for (namespace, entitiesById) in entities {
      instaqlData[namespace] = Array(entitiesById.values)
    }
    
    return instaqlData
  }
}
