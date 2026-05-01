import Models

// MARK: - Video Player

extension MediaItem {
    /// Returns a compact subtitle string suitable for the video player's top bar.
    /// For episodes: "S1 E3 · Series Name". For others: production year as string.
    var playerTopBarSubtitle: String? {
        if mediaType == .episode {
            var parts: [String] = []
            if let s = parentIndexNumber, let e = indexNumber {
                parts.append("S\(s) E\(e)")
            }
            if let series = seriesName {
                parts.append(series)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        return productionYear.map { String($0) }
    }
}

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
