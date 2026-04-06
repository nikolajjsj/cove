import Foundation
import Models

/// Optional capability protocol for servers that support music.
public protocol MusicProvider: MediaServerProvider {
    func albums(artist: ArtistID) async throws -> [Album]
    func tracks(album: AlbumID) async throws -> [Track]
    func playlists() async throws -> [Playlist]
    func lyrics(track: TrackID) async throws -> Lyrics?

    // Playlist CRUD
    func playlistTracks(playlist: PlaylistID) async throws -> [Track]
    func createPlaylist(name: String, trackIds: [ItemID]) async throws -> Playlist?
    func addToPlaylist(playlist: PlaylistID, trackIds: [ItemID]) async throws
    func removeFromPlaylist(playlist: PlaylistID, entryIds: [String]) async throws
    func renamePlaylist(playlist: PlaylistID, name: String) async throws
    func deletePlaylist(playlist: PlaylistID) async throws

    // Favorites
    func setFavorite(itemId: ItemID, isFavorite: Bool) async throws

    // Instant Mix (Radio)
    func instantMix(for itemId: ItemID, limit: Int) async throws -> [Track]
}
