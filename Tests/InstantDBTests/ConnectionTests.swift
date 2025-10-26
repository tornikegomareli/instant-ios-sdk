import XCTest
@testable import InstantDB

final class ConnectionTests: XCTestCase {
  
  func testConnectionStateInitiallyDisconnected() {
    let appID = "00000000-0000-0000-0000-000000000000"
    let client = InstantClient(appID: appID)
    
    XCTAssertEqual(client.connectionState, .disconnected)
    XCTAssertFalse(client.isAuthenticated)
    XCTAssertNil(client.sessionID)
  }
  
  func testConnectionStateInitiallyConnected() {
    let appID = "a8a567cc-34a7-41b4-8802-d81186ad7014"
    let client = InstantClient(appID: appID)
    client.connect()
    
    XCTAssertEqual(client.connectionState, .connected)
  }
  
  func testInvalidAppIDFormat() {
    let appID = "invalid-app-id"
    let client = InstantClient(appID: appID)
    
    XCTAssertNotNil(client)
  }
  
  func testMessageEncoding() throws {
    let message = InitMessage(
      clientEventId: "test-event-id",
      appId: "test-app-id",
      refreshToken: nil
    )
    
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    
    let data = try encoder.encode(message)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    
    XCTAssertEqual(json?["op"] as? String, "init")
    XCTAssertEqual(json?["client-event-id"] as? String, "test-event-id")
    XCTAssertEqual(json?["app-id"] as? String, "test-app-id")
  }
  
  func testAttributeDecoding() throws {
    let json = """
        {
            "id": "attr-123",
            "forward-identity": ["id", "users", "email"],
            "reverse-identity": null,
            "value-type": "string",
            "cardinality": "one",
            "unique": true,
            "indexed": true,
            "checked-data-type": "string"
        }
        """
    
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    let data = json.data(using: .utf8)!
    let attribute = try decoder.decode(Attribute.self, from: data)
    
    XCTAssertEqual(attribute.id, "attr-123")
    XCTAssertEqual(attribute.forwardIdentity, ["id", "users", "email"])
    XCTAssertEqual(attribute.valueType, .string)
    XCTAssertEqual(attribute.cardinality, .one)
    XCTAssertTrue(attribute.unique)
    XCTAssertTrue(attribute.indexed)
  }
}
