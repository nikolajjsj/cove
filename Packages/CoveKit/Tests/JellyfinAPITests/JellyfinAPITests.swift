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

    // MARK: - Jellyfin 12.0 Authorization

    /// Jellyfin 12.0 disables the legacy `api_key` query parameter by default.
    /// Every URL handed to AVPlayer or a background download task must therefore
    /// authenticate with `ApiKey`.
    func testStreamURLsUseModernApiKeyQueryParameter() throws {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        client.setAccessToken("tok")
        client.setUserId("user-1")

        let urls: [URL] = try [
            XCTUnwrap(client.audioStreamURL(itemId: "a1")),
            XCTUnwrap(client.videoStreamURL(itemId: "v1", mediaSourceId: "src")),
            XCTUnwrap(
                client.subtitleURL(itemId: "v1", mediaSourceId: "src", subtitleIndex: 2)),
            XCTUnwrap(client.downloadURL(itemId: "d1")),
            XCTUnwrap(client.compatibleDownloadURL(itemId: "d1", mediaSourceId: "src")),
        ]

        for url in urls {
            let items =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let names = items.map(\.name)
            XCTAssertTrue(
                names.contains("ApiKey"), "\(url.path) is missing the ApiKey parameter")
            XCTAssertFalse(
                names.contains("api_key"),
                "\(url.path) still uses the legacy api_key parameter")
            XCTAssertEqual(items.first { $0.name == "ApiKey" }?.value, "tok")
        }
    }

    // MARK: - Transcode URL Resolution

    /// A Jellyfin reachable at a sub-path (behind a reverse proxy) must keep that
    /// prefix when the server-relative `TranscodingUrl` is turned absolute.
    func testHLSStreamURLPreservesBasePathPrefix() throws {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com/jellyfin")!)
        let url = try XCTUnwrap(
            client.hlsStreamURL(transcodingPath: "/videos/abc/master.m3u8?PlaySessionId=xyz"))

        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/jellyfin/videos/abc/master.m3u8?PlaySessionId=xyz")
    }

    func testHLSStreamURLAtRootAndWithTrailingSlash() throws {
        let root = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        XCTAssertEqual(
            try XCTUnwrap(root.hlsStreamURL(transcodingPath: "/videos/abc/master.m3u8"))
                .absoluteString,
            "https://example.com/videos/abc/master.m3u8")

        let trailing = JellyfinAPIClient(baseURL: URL(string: "https://example.com/jf/")!)
        XCTAssertEqual(
            try XCTUnwrap(trailing.hlsStreamURL(transcodingPath: "/videos/abc/master.m3u8"))
                .absoluteString,
            "https://example.com/jf/videos/abc/master.m3u8")
    }

    /// `TranscodingUrl` is chosen by the server. RFC 3986 resolution discards the
    /// base whenever the reference carries its own scheme, so resolving it directly
    /// would let a compromised server redirect playback — and the access token in
    /// the query — to a host of its choosing.
    func testHLSStreamURLPinsHostAndSchemeToTheServer() throws {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://jellyfin.example.com/jf")!)

        let hostile = [
            "https://evil.com/x.m3u8?ApiKey=TOK",
            "http://evil.com/x.m3u8",
            "///evil.com/x.m3u8",
            "//evil.com/x.m3u8",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "https://user:pw@evil.com/x",
        ]

        for payload in hostile {
            let url = try XCTUnwrap(
                client.hlsStreamURL(transcodingPath: payload), "\(payload) produced no URL")
            XCTAssertEqual(url.scheme, "https", "\(payload) changed the scheme")
            XCTAssertEqual(url.host, "jellyfin.example.com", "\(payload) changed the host")
            XCTAssertNil(url.user, "\(payload) injected userinfo")
            XCTAssertTrue(
                url.path.hasPrefix("/jf/"), "\(payload) escaped the base path: \(url.path)")
        }
    }

    /// The server legitimately puts the play session in the query, so it has to
    /// survive having the authority replaced.
    func testHLSStreamURLKeepsTheServerSuppliedQuery() throws {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        let url = try XCTUnwrap(
            client.hlsStreamURL(
                transcodingPath: "/videos/abc/master.m3u8?PlaySessionId=xyz&ApiKey=TOK"))

        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/videos/abc/master.m3u8?PlaySessionId=xyz&ApiKey=TOK")
    }

    func testHLSStreamURLRejectsEmptyPath() {
        let client = JellyfinAPIClient(baseURL: URL(string: "https://example.com")!)
        XCTAssertNil(client.hlsStreamURL(transcodingPath: ""))
    }
}
