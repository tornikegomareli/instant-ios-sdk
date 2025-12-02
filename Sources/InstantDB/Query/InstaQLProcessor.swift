import Foundation

/// Simple InstaQL processor for v0 (no optimistic updates, no relations yet)
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
    
    /// Group triples by entity and namespace
    var entities: [String: [String: [String: Any]]] = [:] // namespace -> entityId -> attributes
    
    for triple in triples {
      guard triple.count >= 3,
            let entityId = triple[0] as? String,
            let attrId = triple[1] as? String else {
        continue
      }
      
      let value = triple[2]
      
      guard let attr = attributes.first(where: { $0.id == attrId }) else {
        continue
      }
      
      let namespace = attr.forwardIdentity[1]
      let attrName = attr.forwardIdentity[2]
      
      /// Skip special handling for 'id' attribute for now (it's the entity ID itself)
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
      
      // Add attribute to entity
      entities[namespace]?[entityId]?[attrName] = value
    }
    
    // Convert to InstaQL format: {namespace: [entity1, entity2, ...]}
    var instaqlData: [String: Any] = [:]
    for (namespace, entitiesById) in entities {
      instaqlData[namespace] = Array(entitiesById.values)
    }
    
    return instaqlData
  }
}
