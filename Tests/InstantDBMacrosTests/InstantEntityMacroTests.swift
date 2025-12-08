import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(InstantDBMacros)
import InstantDBMacros

final class InstantEntityMacroTests: XCTestCase {
  let testMacros: [String: Macro.Type] = [
    "InstantEntity": InstantEntityMacro.self
  ]
  
  func testMacroGeneratesNamespace() throws {
    assertMacroExpansion(
      #"""
      @InstantEntity("goals")
      struct Goal {
        let id: String
        var title: String
      }
      """#,
      expandedSource: #"""
      struct Goal {
        let id: String
        var title: String
      
        static var namespace: String {
          "goals"
        }
      
        static func create(
            id: String = UUID().uuidString,
            title: String
        ) -> TransactionChunk {
            var attrs: [String: Any] = [:]
            attrs["title"] = title
      
            return TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["update", "goals", id, attrs]]
            )
        }
      
        static func update(
            id: String,
            title: String? = nil
        ) -> TransactionChunk {
            var attrs: [String: Any] = [:]
            if let title = title {
              attrs["title"] = title
            }
      
            return TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["update", "goals", id, attrs]]
            )
        }
      
        static func update(_ entity: Goal) -> TransactionChunk {
            let encoder = JSONEncoder()
            let data = (try? encoder.encode(entity)) ?? Data()
            let attrs = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
      
            return TransactionChunk(
                namespace: "goals",
                id: entity.id,
                ops: [["update", "goals", entity.id, attrs]]
            )
        }
      
        static func merge(
            id: String,
            title: String? = nil
        ) -> TransactionChunk {
            var attrs: [String: Any] = [:]
            if let title = title {
              attrs["title"] = title
            }
      
            return TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["merge", "goals", id, attrs]]
            )
        }
      
        static func delete(id: String) -> TransactionChunk {
            TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["delete", "goals", id]]
            )
        }
      
        static func link(id: String, _ relationship: String, to ids: [String]) -> TransactionChunk {
            TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["link", "goals", id, [relationship: ids]]]
            )
        }
      
        static func link(id: String, _ relationship: String, to linkedId: String) -> TransactionChunk {
            link(id: id, relationship, to: [linkedId])
        }
      
        static func unlink(id: String, _ relationship: String, from ids: [String]) -> TransactionChunk {
            TransactionChunk(
                namespace: "goals",
                id: id,
                ops: [["unlink", "goals", id, [relationship: ids]]]
            )
        }
      
        static func unlink(id: String, _ relationship: String, from linkedId: String) -> TransactionChunk {
            unlink(id: id, relationship, from: [linkedId])
        }
      }
      
      extension Goal: InstantEntity, Identifiable, Codable {
      }
      """#,
      macros: testMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testMacroErrorOnClass() throws {
    assertMacroExpansion(
      #"""
      @InstantEntity("items")
      class Item {
        let id: String
      }
      """#,
      expandedSource: #"""
      class Item {
        let id: String
      }
      
      extension Item: InstantEntity, Identifiable, Codable {
      }
      """#,
      diagnostics: [
        DiagnosticSpec(message: "@InstantEntity can only be applied to structs", line: 1, column: 1)
      ],
      macros: testMacros
    )
  }
  
  func testMacroErrorOnMissingNamespace() throws {
    assertMacroExpansion(
      #"""
      @InstantEntity
      struct Item {
        let id: String
      }
      """#,
      expandedSource: #"""
      struct Item {
        let id: String
      }

      extension Item: InstantEntity, Identifiable, Codable {
      }
      """#,
      diagnostics: [
        DiagnosticSpec(message: "@InstantEntity requires a string literal namespace argument", line: 1, column: 1)
      ],
      macros: testMacros
    )
  }
}
#endif
