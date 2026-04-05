import Foundation
import Models

/// Optional capability protocol for servers that support music.
public protocol MusicProvider: MediaServerProvider {
    func albums(artist: ArtistID) async throws -> [Album]
    func tracks(album: AlbumID) async throws -> [Track]
    func playlists() async throws -> [Playlist]
    func lyrics(track: TrackID) async throws -> Lyrics?
}
