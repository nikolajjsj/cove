import Foundation

/// Response DTO for `GET /System/Info/Public`
/// Used for server discovery before authentication.
public struct PublicSystemInfo: Codable, Sendable {
    public let serverName: String?
    public let version: String?
    public let id: String?
    public let localAddress: String?
    public let operatingSystem: String?
    public let startupWizardCompleted: Bool?

    public init(
        serverName: String? = nil,
        version: String? = nil,
        id: String? = nil,
        localAddress: String? = nil,
        operatingSystem: String? = nil,
        startupWizardCompleted: Bool? = nil
    ) {
        self.serverName = serverName
        self.version = version
        self.id = id
        self.localAddress = localAddress
        self.operatingSystem = operatingSystem
        self.startupWizardCompleted = startupWizardCompleted
    }

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
        case localAddress = "LocalAddress"
        case operatingSystem = "OperatingSystem"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}
