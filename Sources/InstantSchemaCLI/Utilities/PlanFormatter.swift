import Foundation
import InstantDB

/// Formats schema plan output for CLI display
enum PlanFormatter {
  static func printPlan(_ plan: SchemaPlanResponse) {
    print("")
    for step in plan.steps {
      let badge = stepBadge(for: step.type)
      let description = formatDescription(step)
      print("\(badge) \(description)")
      
      if let secondary = formatSecondaryDetails(step) {
        print("  \(Terminal.italic(Terminal.gray(secondary)))")
      }
    }
  }
  
  static func stepBadge(for type: String) -> String {
    switch type {
    case "add-attr":
      return Terminal.greenBadge("+ CREATE ATTR")
    case "delete-attr":
      return Terminal.redBadge("- DELETE ATTR")
    case "update-attr":
      return Terminal.yellowBadge("* UPDATE ATTR")
    case "add-namespace":
      return Terminal.greenBadge("+ CREATE NAMESPACE")
    case "delete-namespace":
      return Terminal.redBadge("- DELETE NAMESPACE")
    case "add-link":
      return Terminal.greenBadge("+ CREATE LINK")
    case "delete-link":
      return Terminal.redBadge("- DELETE LINK")
    case "index":
      return Terminal.blueBadge("+ CREATE INDEX")
    case "remove-index":
      return Terminal.blueBadge("- DELETE INDEX")
    case "unique":
      return Terminal.blueBadge("* MAKE UNIQUE")
    case "remove-unique":
      return Terminal.blueBadge("- REMOVE UNIQUE")
    case "required":
      return Terminal.blueBadge("+ MAKE REQUIRED")
    case "remove-required":
      return Terminal.blueBadge("- MAKE OPTIONAL")
    case "check-data-type":
      return Terminal.blueBadge("+ SET DATA TYPE")
    default:
      return Terminal.gray("[\(type)]")
    }
  }
  
  static func formatDescription(_ step: SchemaPlanStep) -> String {
    if let identity = step.details.forwardIdentity {
      return Terminal.bold("\(identity.entityName)") + ".\(identity.attributeName)"
    }
    
    if let attrId = step.details.attrId {
      return attrId
    }
    
    return ""
  }
  
  static func formatSecondaryDetails(_ step: SchemaPlanStep) -> String? {
    var details: [String] = []
    
    if let valueType = step.details.valueType {
      details.append("type: \(valueType)")
    }
    
    if step.details.indexed == true {
      details.append("indexed")
    }
    
    if step.details.unique == true {
      details.append("unique")
    }
    
    return details.isEmpty ? nil : details.joined(separator: ", ")
  }
}
