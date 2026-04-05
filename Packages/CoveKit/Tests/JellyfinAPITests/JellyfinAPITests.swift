import XCTest

@testable import JellyfinAPI

final class JellyfinAPITests: XCTestCase {
    func testJellyfinAPIClientInitialization() {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        XCTAssertNotNil(client)
        XCTAssertNil(client.accessToken)
    }

    func testSetAccessToken() {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        XCTAssertNil(client.accessToken)
        client.setAccessToken("test-token-123")
        XCTAssertEqual(client.accessToken, "test-token-123")
        client.setAccessToken(nil)
        XCTAssertNil(client.accessToken)
    }

    func testPublicSystemInfoDecoding() throws {
        let json = """
            {
                "ServerName": "My Jellyfin",
                "Version": "10.9.0",
                "Id": "abc123",
                "LocalAddress": "http://192.168.1.100:8096",
                "OperatingSystem": "Linux",
                "StartupWizardCompleted": true
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let info = try decoder.decode(PublicSystemInfo.self, from: json)

        XCTAssertEqual(info.serverName, "My Jellyfin")
        XCTAssertEqual(info.version, "10.9.0")
        XCTAssertEqual(info.id, "abc123")
        XCTAssertEqual(info.operatingSystem, "Linux")
        XCTAssertEqual(info.startupWizardCompleted, true)
    }

    func testAuthenticationResultDecoding() throws {
        let json = """
            {
                "User": {
                    "Name": "testuser",
                    "ServerId": "server-1",
                    "Id": "user-abc",
                    "HasPassword": true,
                    "HasConfiguredPassword": true
                },
                "AccessToken": "token-xyz-789",
                "ServerId": "server-1"
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let result = try decoder.decode(AuthenticationResult.self, from: json)

        XCTAssertEqual(result.accessToken, "token-xyz-789")
        XCTAssertEqual(result.serverId, "server-1")
        XCTAssertEqual(result.user?.name, "testuser")
        XCTAssertEqual(result.user?.id, "user-abc")
    }

    func testAuthenticateByNameRequestEncoding() throws {
        let request = AuthenticateByNameRequest(username: "admin", password: "secret")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]

        XCTAssertEqual(dict["Username"], "admin")
        XCTAssertEqual(dict["Pw"], "secret")
    }

    func testAuthHeaderValue() {
        let header = JellyfinAuthHeader.headerValue(token: nil)
        XCTAssertTrue(header.contains("MediaBrowser Client=\"Cove\""))
        XCTAssertFalse(header.contains("Token="))

        let authHeader = JellyfinAuthHeader.headerValue(token: "my-token")
        XCTAssertTrue(authHeader.contains("Token=\"my-token\""))
        XCTAssertTrue(authHeader.contains("MediaBrowser Client=\"Cove\""))
    }
}
