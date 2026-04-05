import Foundation

/// Request body for `POST /Users/AuthenticateByName`
public struct AuthenticateByNameRequest: Codable, Sendable {
    public let username: String
    public let pw: String

    public init(username: String, password: String) {
        self.username = username
        self.pw = password
    }

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

/// Response DTO for `POST /Users/AuthenticateByName`
public struct AuthenticationResult: Codable, Sendable {
    public let user: UserDto?
    public let accessToken: String?
    public let serverId: String?

    public init(user: UserDto? = nil, accessToken: String? = nil, serverId: String? = nil) {
        self.user = user
        self.accessToken = accessToken
        self.serverId = serverId
    }

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

/// Nested user info within authentication response.
public struct UserDto: Codable, Sendable {
    public let name: String?
    public let serverId: String?
    public let id: String?
    public let hasPassword: Bool?
    public let hasConfiguredPassword: Bool?

    public init(
        name: String? = nil,
        serverId: String? = nil,
        id: String? = nil,
        hasPassword: Bool? = nil,
        hasConfiguredPassword: Bool? = nil
    ) {
        self.name = name
        self.serverId = serverId
        self.id = id
        self.hasPassword = hasPassword
        self.hasConfiguredPassword = hasConfiguredPassword
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case serverId = "ServerId"
        case id = "Id"
        case hasPassword = "HasPassword"
        case hasConfiguredPassword = "HasConfiguredPassword"
    }
}
