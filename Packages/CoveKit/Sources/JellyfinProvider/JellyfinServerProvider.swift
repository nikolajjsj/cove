import Foundation
import JellyfinAPI
import MediaServerKit
import Models
import Networking
import os

/// Jellyfin implementation of all MediaServerKit protocols.
/// This is the only module that knows about Jellyfin specifics.
public final class JellyfinServerProvider: MediaServerProvider,
    MusicProvider, VideoProvider, TranscodingProvider,
    PlaybackReportingProvider, DownloadableProvider
{
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "JellyfinProvider")
    private let keychain: KeychainService
    private let state: ProviderState

    public init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
        self.state = ProviderState()
    }

    // MARK: - Connection

    public func connect(url: URL, credentials: Credentials) async throws -> ServerConnection {
        logger.info("Connecting to Jellyfin server at \(url.absoluteString)")

        let client = JellyfinAPIClient(baseURL: url)

        // Step 1: Discover server info
        let serverInfo = try await client.getPublicSystemInfo()
        let serverName = serverInfo.serverName ?? url.host ?? "Jellyfin Server"
        logger.info("Discovered server: \(serverName) (v\(serverInfo.version ?? "unknown"))")

        // Step 2: Authenticate
        let authResult = try await client.authenticateByName(
            username: credentials.username,
            password: credentials.password
        )

        guard let token = authResult.accessToken else {
            throw AppError.authFailed(reason: "Server did not return an access token")
        }

        guard let userId = authResult.user?.id else {
            throw AppError.authFailed(reason: "Server did not return a user ID")
        }

        // Step 3: Build the connection
        let connection = ServerConnection(
            name: serverName,
            url: url,
            userId: userId,
            serverType: .jellyfin
        )

        // Step 4: Persist token to Keychain
        try keychain.setToken(token, forServerID: connection.id.uuidString)
        logger.info("Token stored in Keychain for server \(connection.id.uuidString)")

        // Step 5: Store client for subsequent requests
        client.setAccessToken(token)
        state.set(client: client, connection: connection)

        logger.info("Successfully connected to \(serverName) as user \(userId)")
        return connection
    }

    public func disconnect() async {
        if let connection = state.connection {
            keychain.deleteToken(forServerID: connection.id.uuidString)
            logger.info("Disconnected from \(connection.name)")
        }
        state.clear()
    }

    /// Restore a previous connection using a persisted token.
    /// Call this on app launch with a stored `ServerConnection`.
    public func restore(connection: ServerConnection) -> Bool {
        guard let token = keychain.token(forServerID: connection.id.uuidString) else {
            logger.warning("No token found for server \(connection.id.uuidString)")
            return false
        }
        let client = JellyfinAPIClient(baseURL: connection.url)
        client.setAccessToken(token)
        state.set(client: client, connection: connection)
        logger.info("Restored connection to \(connection.name)")
        return true
    }

    // MARK: - Library Browsing

    public func libraries() async throws -> [MediaLibrary] {
        guard let client = state.client else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        let folders = try await client.getVirtualFolders()
        return folders.compactMap { JellyfinMapper.mapLibrary($0) }
    }

    public func items(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions)
        async throws -> [MediaItem]
    {
        guard let client = state.client, let userId = client.userId ?? state.connection?.userId
        else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        let result = try await client.getItems(
            userId: userId,
            parentId: library.id.rawValue,
            sortBy: JellyfinMapper.sortByString(sort.field),
            sortOrder: JellyfinMapper.sortOrderString(sort.order),
            limit: filter.limit,
            startIndex: filter.startIndex,
            searchTerm: filter.searchTerm,
            isFavorite: filter.isFavorite
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func item(id: ItemID) async throws -> MediaItem {
        guard let client = state.client, let userId = client.userId ?? state.connection?.userId
        else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        let dto = try await client.getItem(userId: userId, itemId: id.rawValue)
        guard let item = JellyfinMapper.mapItem(dto) else {
            throw AppError.itemNotFound(id: id)
        }
        return item
    }

    public func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL? {
        guard let client = state.client else { return nil }
        let maxWidth = maxSize.map { Int($0.width) }
        let maxHeight = maxSize.map { Int($0.height) }
        return client.imageURL(
            itemId: item.id.rawValue,
            imageType: JellyfinMapper.imageTypeString(type),
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )
    }

    public func search(query: String, mediaTypes: [MediaType]) async throws -> SearchResults {
        guard let client = state.client, let userId = client.userId ?? state.connection?.userId
        else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        let result = try await client.getItems(
            userId: userId,
            searchTerm: query
        )
        let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
        return SearchResults(items: items)
    }

    // MARK: - MusicProvider (Phase 4)

    public func albums(artist: ArtistID) async throws -> [Album] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func tracks(album: AlbumID) async throws -> [Track] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func playlists() async throws -> [Playlist] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func lyrics(track: TrackID) async throws -> Lyrics? {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    // MARK: - VideoProvider (Phase 5)

    public func seasons(series: SeriesID) async throws -> [Season] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func episodes(season: SeasonID) async throws -> [Episode] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func resumeItems() async throws -> [MediaItem] {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func streamURL(for item: MediaItem, profile: DeviceProfile?) async throws -> StreamInfo {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    // MARK: - TranscodingProvider (Phase 5)

    public func deviceProfile() -> DeviceProfile {
        DeviceProfile(name: "Cove iOS")  // Stub — Phase 5
    }

    public func transcodedStreamURL(for item: MediaItem, profile: DeviceProfile) async throws -> URL
    {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    // MARK: - PlaybackReportingProvider (Phase 4/5)

    public func reportPlaybackStart(item: MediaItem, position: TimeInterval) async throws {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    public func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws {
        throw AppError.unknown(underlying: NotImplementedError())
    }

    // MARK: - DownloadableProvider (Phase 6)

    public func downloadURL(for item: MediaItem, profile: DeviceProfile?) async throws -> URL {
        throw AppError.unknown(underlying: NotImplementedError())
    }
}

// MARK: - Internal Helpers

/// Thread-safe mutable state for the provider.
private final class ProviderState: @unchecked Sendable {
    private let lock = NSLock()
    private var _client: JellyfinAPIClient?
    private var _connection: ServerConnection?

    var client: JellyfinAPIClient? {
        lock.lock()
        defer { lock.unlock() }
        return _client
    }

    var connection: ServerConnection? {
        lock.lock()
        defer { lock.unlock() }
        return _connection
    }

    func set(client: JellyfinAPIClient, connection: ServerConnection) {
        lock.lock()
        defer { lock.unlock() }
        _client = client
        _connection = connection
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _client = nil
        _connection = nil
    }
}

/// Placeholder error for not-yet-implemented methods.
private struct NotImplementedError: Error, CustomStringConvertible {
    var description: String { "This feature is not yet implemented" }
}
