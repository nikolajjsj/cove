import Models

// MARK: - MediaItem ↔ Track Conversion

extension MediaItem {
    /// Convert a `MediaItem` to a `Track` for audio queue operations.
    ///
    /// Extracts all available metadata — track/disc numbers, audio stream
    /// codec/bitRate/sampleRate/channelCount — so the player queue and
    /// Track Info sheet always have complete data regardless of which
    /// view initiated playback.
    var asTrack: Track {
        let audioStream = mediaStreams?.first(where: { $0.type == .audio })
        return Track(
            id: TrackID(id.rawValue),
            title: title,
            albumId: albumId.map { AlbumID($0.rawValue) },
            albumName: albumName,
            artistName: artistName,
            trackNumber: indexNumber,
            discNumber: parentIndexNumber,
            duration: runtime,
            codec: audioStream?.codec,
            bitRate: audioStream?.bitrate,
            sampleRate: audioStream?.sampleRate,
            channelCount: audioStream?.channels,
            genres: genres,
            userData: userData
        )
    }
}
