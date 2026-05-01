import CoveUI
import Models

extension MetadataPill {

    /// Builds the standard set of metadata pills for a video detail view
    /// (movie or episode).
    ///
    /// Includes rating pills, media stream info (resolution, HDR, video codec,
    /// bitrate, audio channels, audio codec), and user data indicators
    /// (played status, play count).
    ///
    /// ```swift
    /// MetadataPillsView(
    ///     MetadataPill.videoDetailPills(for: item, displayItem: displayItem)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - item: The navigation-provided item (always available).
    ///   - displayItem: The fully-fetched item with enriched data (people,
    ///     provider IDs, media streams). Falls back gracefully when fields are nil.
    ///   - effectiveUserData: The effective user data resolved from `UserDataStore`,
    ///     reflecting live optimistic overrides. Pass
    ///     `userDataStore.userData(for: item.id, fallback: item.userData)`.
    /// - Returns: An ordered array of metadata pills.
    static func videoDetailPills(
        for item: MediaItem,
        displayItem: MediaItem,
        effectiveUserData: UserData? = nil
    ) -> [MetadataPill] {
        var pills = ratingPills(
            communityRating: item.communityRating,
            criticRating: item.criticRating,
            hasImdb: displayItem.providerIds?.imdb != nil
        )

        // Media stream pills
        if let streams = displayItem.mediaStreams {

            // Video stream: resolution → HDR → codec → bitrate
            if let videoStream = streams.first(where: { $0.type == .video }) {
                if let pill = resolution(width: videoStream.width ?? 0) {
                    pills.append(pill)
                }
                if let pill = hdr(
                    videoRange: videoStream.videoRange,
                    videoRangeType: videoStream.videoRangeType
                ) {
                    pills.append(pill)
                }
                if let pill = videoCodec(videoStream.codec) {
                    pills.append(pill)
                }
                if let pill = bitrate(videoStream.bitrate) {
                    pills.append(pill)
                }
            }

            // Audio stream: channels → codec
            if let audioStream = streams.first(where: { $0.type == .audio }) {
                if let pill = audioChannels(audioStream.channels ?? 0) {
                    pills.append(pill)
                }
                if let pill = audioCodec(audioStream.codec) {
                    pills.append(pill)
                }
            }
        }

        // User data pills
        if let userData = effectiveUserData {
            if userData.isPlayed {
                pills.append(.played)
            }
            if let pill = playCount(userData.playCount) {
                pills.append(pill)
            }
        }

        return pills
    }
}
