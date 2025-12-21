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
    
    // Track entity order per namespace to preserve server ordering
    // The server returns entities in the correct order based on orderBy clause
    var entityOrder: [String: [String]] = [:]
    // namespace -> [entityId1, entityId2, ...] in order of first appearance
    
    // Track ref relationships for BOTH directions
    // Forward: (parentNamespace, parentId, linkLabel, linkedId, linkedNamespace)
    // Reverse: (childNamespace, childId, reverseLinkLabel, parentId, parentNamespace)
    struct RefLink {
      let parentNamespace: String
      let parentId: String
      let linkLabel: String
      let linkedId: String
      let linkedNamespace: String
    }
    
    var forwardLinks: [RefLink] = []
    var reverseLinks: [RefLink] = []
    
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
        entityOrder[namespace] = []
      }
      
      // Initialize entity if needed, tracking order of first appearance
      if entities[namespace]?[entityId] == nil {
        entities[namespace]?[entityId] = ["id": entityId]
        // Track order - only add if not already present
        if !(entityOrder[namespace]?.contains(entityId) ?? false) {
          entityOrder[namespace]?.append(entityId)
        }
      }
      
      // Handle ref attributes (links) specially
      if attr.valueType == .ref {
        // The value is the ID of the linked entity
        if let linkedId = value as? String {
          // Forward link: parent → child (e.g., profiles.posts)
          if let reverseIdentity = attr.reverseIdentity,
             reverseIdentity.count >= 3 {
            // reverseIdentity = [identId, linkedNamespace, reverseLabel]
            let linkedNamespace = reverseIdentity[1]
            
            forwardLinks.append(RefLink(
              parentNamespace: namespace,
              parentId: entityId,
              linkLabel: attrName,
              linkedId: linkedId,
              linkedNamespace: linkedNamespace
            ))
            
            // Reverse link: child → parent (e.g., posts.author)
            let reverseLabel = reverseIdentity[2]
            reverseLinks.append(RefLink(
              parentNamespace: linkedNamespace,
              parentId: linkedId,
              linkLabel: reverseLabel,
              linkedId: entityId,
              linkedNamespace: namespace
            ))
          }
        }
      } else {
        // Regular attribute - add directly to entity
        entities[namespace]?[entityId]?[attrName] = value
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
          // First value - store as single entity (has-one)
          // The TypeScript client uses cardinality inference to decide array vs single
          // For simplicity, we'll store as single and let the decoder handle it
          entities[link.parentNamespace]?[link.parentId]?[link.linkLabel] = shallowEntity
        }
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
    // Use entityOrder to preserve the server's ordering (important for orderBy queries)
    var instaqlData: [String: Any] = [:]
    for (namespace, entitiesById) in entities {
      // Get entities in the order they first appeared (server's order)
      if let orderedIds = entityOrder[namespace] {
        let orderedEntities = orderedIds.compactMap { entitiesById[$0] }
        instaqlData[namespace] = orderedEntities
      } else {
        // Fallback to unordered if no order tracking (shouldn't happen)
        instaqlData[namespace] = Array(entitiesById.values)
      }
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
