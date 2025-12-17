import Foundation

// MARK: - Transaction Step Types

/// The types of operations that can be applied to the store.
///
/// These match the wire protocol operations from InstantDB:
/// - `add-triple`: Add a new fact
/// - `retract-triple`: Remove a fact
/// - `deep-merge-triple`: Merge JSON objects
/// - `delete-entity`: Delete an entire entity
/// - `add-attr`: Add a new attribute definition
/// - `delete-attr`: Delete an attribute definition
/// - `update-attr`: Update an attribute definition
public enum TxAction: String, Sendable {
  case addTriple = "add-triple"
  case retractTriple = "retract-triple"
  case deepMergeTriple = "deep-merge-triple"
  case deleteEntity = "delete-entity"
  case addAttr = "add-attr"
  case deleteAttr = "delete-attr"
  case updateAttr = "update-attr"
  case restoreAttr = "restore-attr"
  case ruleParams = "rule-params"
}

/// A single step in a transaction.
///
/// Transaction steps are the low-level operations that modify the store.
/// They are generated from high-level operations like `create`, `update`, `delete`.
public struct TxStep: @unchecked Sendable {
  public let action: TxAction
  public let args: [Any]
  
  public init(action: TxAction, args: [Any]) {
    self.action = action
    self.args = args
  }
  
  /// Creates from an array representation `[action, ...args]`
  public init?(fromArray array: [Any]) {
    guard let actionStr = array.first as? String,
          let action = TxAction(rawValue: actionStr) else {
      return nil
    }
    self.action = action
    self.args = Array(array.dropFirst())
  }
  
  /// Converts to array representation
  public func toArray() -> [Any] {
    [action.rawValue] + args
  }
}

// MARK: - Store Transactions

/// Applies a series of transaction steps to a store.
///
/// This is the main entry point for applying mutations to the local store.
/// It handles all the different operation types and maintains consistency.
///
/// - Parameters:
///   - store: The triple store to modify
///   - attrsStore: The attribute store (may be modified by attr operations)
///   - txSteps: The transaction steps to apply
/// - Returns: The modified stores
///
/// - Note: This is ported from `instant/client/packages/core/src/store.ts` transact function
public func applyTransaction(
  store: TripleStore,
  attrsStore: AttrsStore,
  txSteps: [[Any]]
) -> (store: TripleStore, attrsStore: AttrsStore) {
  for stepArray in txSteps {
    guard let step = TxStep(fromArray: stepArray) else {
      print("[InstantDB] Warning: Invalid tx step: \(stepArray)")
      continue
    }
    applyTxStep(store: store, attrsStore: attrsStore, step: step)
  }
  
  return (store, attrsStore)
}

/// Applies a single transaction step to the store.
private func applyTxStep(store: TripleStore, attrsStore: AttrsStore, step: TxStep) {
  switch step.action {
  case .addTriple:
    applyAddTriple(store: store, attrsStore: attrsStore, args: step.args)
    
  case .retractTriple:
    applyRetractTriple(store: store, attrsStore: attrsStore, args: step.args)
    
  case .deepMergeTriple:
    applyMergeTriple(store: store, attrsStore: attrsStore, args: step.args)
    
  case .deleteEntity:
    applyDeleteEntity(store: store, attrsStore: attrsStore, args: step.args)
    
  case .addAttr:
    applyAddAttr(attrsStore: attrsStore, args: step.args)
    
  case .deleteAttr:
    applyDeleteAttr(store: store, attrsStore: attrsStore, args: step.args)
    
  case .updateAttr:
    applyUpdateAttr(store: store, attrsStore: attrsStore, args: step.args)
    
  case .restoreAttr, .ruleParams:
    // No-op for these
    break
  }
}

// MARK: - Triple Operations

private func applyAddTriple(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  // Args: [entityId, attributeId, value, options?]
  guard args.count >= 3 else { return }
  
  let entityId: String
  let attributeId: String
  
  // Handle lookup refs (entityId can be [attrId, value] for lookups)
  if let eid = args[0] as? String {
    entityId = eid
  } else if let lookup = args[0] as? [Any], lookup.count == 2 {
    // Lookup ref - need to resolve
    // For now, skip if we can't resolve
    return
  } else {
    return
  }
  
  guard let aid = args[1] as? String else { return }
  attributeId = aid
  
  let value = TripleValue(fromAny: args[2])
  
  // Get attribute metadata
  let attr = attrsStore.getAttr(attributeId)
  let hasCardinalityOne = attr?.cardinality == .one
  let isRef = attr?.valueType == .ref
  
  let createdAt = ConflictResolution.optimisticTimestamp()
  let triple = Triple(entityId: entityId, attributeId: attributeId, value: value, createdAt: createdAt)
  
  store.addTriple(triple, hasCardinalityOne: hasCardinalityOne, isRef: isRef)
}

private func applyRetractTriple(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  guard args.count >= 3,
        let entityId = args[0] as? String,
        let attributeId = args[1] as? String else { return }
  
  let value = TripleValue(fromAny: args[2])
  let attr = attrsStore.getAttr(attributeId)
  let isRef = attr?.valueType == .ref
  
  // We need to find the existing triple to get its createdAt
  let existingTriples = store.getTriples(entity: entityId, attribute: attributeId, value: value.hashableKey)
  
  for triple in existingTriples {
    store.retractTriple(triple, isRef: isRef)
  }
}

private func applyMergeTriple(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  // Deep merge is for blob attributes - merges JSON objects
  guard args.count >= 3,
        let entityId = args[0] as? String,
        let attributeId = args[1] as? String else { return }
  
  let attr = attrsStore.getAttr(attributeId)
  guard attr?.valueType != .ref else {
    print("[InstantDB] Warning: merge operation is not supported for links")
    return
  }
  
  // Get current value
  let existingTriples = store.getTriples(entity: entityId, attribute: attributeId)
  guard let existingTriple = existingTriples.first else { return }
  
  // Merge the values
  let update = args[2]
  let currentValue = existingTriple.value.toAny()
  let mergedValue = deepMerge(currentValue, update)
  
  let hasCardinalityOne = attr?.cardinality == .one
  let createdAt = ConflictResolution.optimisticTimestamp()
  let newTriple = Triple(
    entityId: entityId,
    attributeId: attributeId,
    value: TripleValue(fromAny: mergedValue),
    createdAt: createdAt
  )
  
  store.addTriple(newTriple, hasCardinalityOne: hasCardinalityOne, isRef: false)
}

private func applyDeleteEntity(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  guard let entityId = args.first as? String else { return }
  store.deleteEntity(entityId, attrsStore: attrsStore)
}

// MARK: - Attribute Operations

private func applyAddAttr(attrsStore: AttrsStore, args: [Any]) {
  guard let attrDict = args.first as? [String: Any] else { return }
  
  // Decode the attribute
  do {
    let data = try JSONSerialization.data(withJSONObject: attrDict)
    let attr = try JSONDecoder().decode(Attribute.self, from: data)
    attrsStore.addAttr(attr)
  } catch {
    print("[InstantDB] Warning: Failed to decode attribute: \(error)")
  }
}

private func applyDeleteAttr(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  guard let attrId = args.first as? String else { return }
  
  // Remove all triples with this attribute
  let triples = store.getTriples(attribute: attrId)
  let attr = attrsStore.getAttr(attrId)
  let isRef = attr?.valueType == .ref
  
  for triple in triples {
    store.retractTriple(triple, isRef: isRef)
  }
  
  attrsStore.deleteAttr(attrId)
}

private func applyUpdateAttr(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  guard let partialDict = args.first as? [String: Any],
        let id = partialDict["id"] as? String else { return }
  
  var partial = PartialAttribute(id: id)
  
  if let cardStr = partialDict["cardinality"] as? String {
    partial.cardinality = Cardinality(rawValue: cardStr)
  }
  if let unique = partialDict["unique"] as? Bool {
    partial.unique = unique
  }
  if let indexed = partialDict["indexed"] as? Bool {
    partial.indexed = indexed
  }
  
  attrsStore.updateAttr(partial)
}

// MARK: - Helpers

/// Deep merges two values (for JSON objects)
private func deepMerge(_ target: Any, _ source: Any) -> Any {
  guard let targetDict = target as? [String: Any],
        let sourceDict = source as? [String: Any] else {
    // If not both dictionaries, source wins
    return source
  }
  
  var result = targetDict
  for (key, sourceValue) in sourceDict {
    if let targetValue = targetDict[key] {
      result[key] = deepMerge(targetValue, sourceValue)
    } else {
      result[key] = sourceValue
    }
  }
  return result
}

