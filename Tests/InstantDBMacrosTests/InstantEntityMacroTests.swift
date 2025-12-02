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

    func testInstantEntityMacroExpansion() throws {
        assertMacroExpansion(
            """
            @InstantEntity("goals")
            struct Goal: Codable {
                let id: String
                var title: String
                var difficulty: Int?
                var completed: Bool?
            }
            """,
            expandedSource: """
            struct Goal: Codable {
                let id: String
                var title: String
                var difficulty: Int?
                var completed: Bool?

                static var namespace: String { "goals" }

                static func create(
                    id: String = UUID().uuidString,
                    title: String,
                    difficulty: Int? = nil,
                    completed: Bool? = nil
                ) -> TransactionChunk {
                    var attrs: [String: Any] = [:]
                    attrs["title"] = title
                    if let difficulty = difficulty { attrs["difficulty"] = difficulty }
                    if let completed = completed { attrs["completed"] = completed }

                    return TransactionChunk(
                        namespace: "goals",
                        id: id,
                        ops: [["update", "goals", id, attrs]]
                    )
                }

                static func update(
                    id: String,
                    title: String? = nil,
                    difficulty: Int?? = nil,
                    completed: Bool?? = nil
                ) -> TransactionChunk {
                    var attrs: [String: Any] = [:]
                    if let title = title { attrs["title"] = title }
                    if let difficulty = difficulty {
                                if let value = difficulty {
                                    attrs["difficulty"] = value
                                } else {
                                    attrs["difficulty"] = NSNull()
                                }
                            }
                    if let completed = completed {
                                if let value = completed {
                                    attrs["completed"] = value
                                } else {
                                    attrs["completed"] = NSNull()
                                }
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
                    title: String? = nil,
                    difficulty: Int?? = nil,
                    completed: Bool?? = nil
                ) -> TransactionChunk {
                    var attrs: [String: Any] = [:]
                    if let title = title { attrs["title"] = title }
                    if let difficulty = difficulty {
                                if let value = difficulty {
                                    attrs["difficulty"] = value
                                } else {
                                    attrs["difficulty"] = NSNull()
                                }
                            }
                    if let completed = completed {
                                if let value = completed {
                                    attrs["completed"] = value
                                } else {
                                    attrs["completed"] = NSNull()
                                }
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
            """,
            macros: testMacros
        )
    }

    func testInstantEntityMacroWithSimpleStruct() throws {
        assertMacroExpansion(
            """
            @InstantEntity("todos")
            struct Todo: Codable {
                let id: String
                var text: String
                var done: Bool
            }
            """,
            expandedSource: """
            struct Todo: Codable {
                let id: String
                var text: String
                var done: Bool

                static var namespace: String { "todos" }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
