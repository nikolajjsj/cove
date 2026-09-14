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
