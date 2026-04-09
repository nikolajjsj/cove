import Models

// MARK: - MediaItem ↔ Track Conversion

extension MediaItem {
    /// Lightweight conversion to a `Track` for audio queue operations.
    ///
    /// Populated from the fields that `MediaItem` carries for audio items.
    /// Used internally by the context menu for Play Next / Play Later actions.
    var asTrack: Track {
        Track(
            id: TrackID(id.rawValue),
            title: title,
            albumId: albumId.map { AlbumID($0.rawValue) },
            albumName: albumName,
            artistName: artistName,
            duration: runtime,
            userData: userData
        )
    }
}
