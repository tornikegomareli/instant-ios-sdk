import Foundation

public struct LinkEndpoint: Sendable {
  public let entityName: String
  public let label: String
  public var cardinality: Cardinality
  public var isRequired: Bool = false
  public var onDelete: OnDeleteAction?

  public init(on entityName: String, label: String, has cardinality: Cardinality) {
    self.entityName = entityName
    self.label = label
    self.cardinality = cardinality
  }
}

public struct SchemaLink: Sendable {
  public let forward: LinkEndpoint
  public let reverse: LinkEndpoint

  public var name: String {
    "\(forward.entityName)\(forward.label.capitalized)"
  }

  public init(forward: LinkEndpoint, reverse: LinkEndpoint) {
    self.forward = forward
    self.reverse = reverse
  }
}

public struct LinkBuilder: Sendable {
  private let forwardEntity: String
  private let forwardLabel: String
  private var forwardCardinality: Cardinality = .one
  private var forwardRequired: Bool = false
  private var forwardOnDelete: OnDeleteAction?

  private var reverseEntity: String?
  private var reverseLabel: String?
  private var reverseCardinality: Cardinality = .many
  private var reverseOnDelete: OnDeleteAction?

  public init(_ forwardEntity: String, _ forwardLabel: String) {
    self.forwardEntity = forwardEntity
    self.forwardLabel = forwardLabel
  }

  public func to(_ reverseEntity: String, _ reverseLabel: String) -> LinkBuilder {
    var copy = self
    copy.reverseEntity = reverseEntity
    copy.reverseLabel = reverseLabel
    return copy
  }

  public func hasOne() -> LinkBuilder {
    var copy = self
    copy.forwardCardinality = .one
    return copy
  }

  public func hasMany() -> LinkBuilder {
    var copy = self
    copy.forwardCardinality = .many
    return copy
  }

  public func required() -> LinkBuilder {
    var copy = self
    copy.forwardRequired = true
    return copy
  }

  public func onDeleteCascade() -> LinkBuilder {
    var copy = self
    copy.forwardOnDelete = .cascade
    return copy
  }

  public func reverseHasOne() -> LinkBuilder {
    var copy = self
    copy.reverseCardinality = .one
    return copy
  }

  public func reverseHasMany() -> LinkBuilder {
    var copy = self
    copy.reverseCardinality = .many
    return copy
  }

  public func reverseOnDeleteCascade() -> LinkBuilder {
    var copy = self
    copy.reverseOnDelete = .cascade
    return copy
  }

  public func build() -> SchemaLink? {
    guard let reverseEntity, let reverseLabel else { return nil }

    var forward = LinkEndpoint(on: forwardEntity, label: forwardLabel, has: forwardCardinality)
    forward.isRequired = forwardRequired
    forward.onDelete = forwardOnDelete

    var reverse = LinkEndpoint(on: reverseEntity, label: reverseLabel, has: reverseCardinality)
    reverse.onDelete = reverseOnDelete

    return SchemaLink(forward: forward, reverse: reverse)
  }
}

public func Link(_ entity: String, _ label: String) -> LinkBuilder {
  LinkBuilder(entity, label)
}
