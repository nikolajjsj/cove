import AppGroup
import JellyfinAPI
import WidgetKit

/// Provides timeline entries for the Cove widget by fetching data from the
/// Jellyfin server using the shared `JellyfinAPIClient`.
///
/// Credentials are read from the App Group shared defaults and Keychain
/// via ``SharedCredentials``, so the widget never stores secrets itself.
///
/// Images are pre-fetched during timeline generation because `AsyncImage`
/// does not work in WidgetKit — widgets are rendered as static snapshots
/// with no live view lifecycle for asynchronous loading.
struct CoveTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> CoveWidgetEntry {
        CoveWidgetEntry(
            date: .now,
            contentType: .continueWatching,
            items: [
                WidgetMediaItem(
                    id: "placeholder",
                    title: "Movie Title",
                    seriesName: nil,
                    seasonEpisodeLabel: nil,
                    playbackProgress: 0.45,
                    imageURL: nil,
                    imageData: nil
                )
            ],
            serverName: "My Server"
        )
    }

    func snapshot(
        for configuration: CoveWidgetIntent,
        in context: Context
    ) async -> CoveWidgetEntry {
        await fetchEntry(for: configuration)
    }

    func timeline(
        for configuration: CoveWidgetIntent,
        in context: Context
    ) async -> Timeline<CoveWidgetEntry> {
        let entry = await fetchEntry(for: configuration)

        // Refresh every 15 minutes
        let nextUpdate =
            Calendar.current.date(
                byAdding: .minute,
                value: 15,
                to: .now
            ) ?? .now

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    // MARK: - Data Fetching

    /// Builds an authenticated `JellyfinAPIClient` from shared credentials,
    /// fetches the appropriate items, and pre-fetches all thumbnail images.
    private func fetchEntry(for configuration: CoveWidgetIntent) async -> CoveWidgetEntry {
        guard let serverURL = SharedCredentials.serverURL,
            let userId = SharedCredentials.userId,
            let authToken = SharedCredentials.authToken
        else {
            return CoveWidgetEntry(
                date: .now,
                contentType: configuration.contentType,
                items: [],
                serverName: nil
            )
        }

        let serverName = SharedCredentials.serverName

        // Build a lightweight client for this request cycle
        let client = JellyfinAPIClient(baseURL: serverURL)
        client.setAccessToken(authToken)
        client.setUserId(userId)

        do {
            let result: ItemsResult

            switch configuration.contentType {
            case .continueWatching:
                result = try await client.getResumeItems(
                    userId: userId,
                    mediaTypes: ["Video"],
                    limit: 6
                )
            case .nextUp:
                result = try await client.getNextUp(userId: userId, limit: 6)
            }

            // Map DTOs to widget items (without images yet)
            var items = (result.items ?? []).compactMap { dto in
                mapToWidgetItem(dto, client: client)
            }

            // Pre-fetch all images in parallel
            items = await prefetchImages(for: items)

            return CoveWidgetEntry(
                date: .now,
                contentType: configuration.contentType,
                items: items,
                serverName: serverName
            )
        } catch {
            return CoveWidgetEntry(
                date: .now,
                contentType: configuration.contentType,
                items: [],
                serverName: serverName
            )
        }
    }

    // MARK: - Image Pre-fetching

    /// Downloads thumbnail images for all items in parallel using a task group.
    ///
    /// Each image is fetched independently so a single failure doesn't block
    /// the others. Items whose images fail to download keep `imageData` as `nil`
    /// and the widget views will show a placeholder instead.
    private func prefetchImages(for items: [WidgetMediaItem]) async -> [WidgetMediaItem] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard let url = item.imageURL else {
                        return (index, nil)
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return (index, data)
                    } catch {
                        return (index, nil)
                    }
                }
            }

            // Collect results and apply image data to a mutable copy
            var updatedItems = items
            for await (index, data) in group {
                let original = updatedItems[index]
                updatedItems[index] = WidgetMediaItem(
                    id: original.id,
                    title: original.title,
                    seriesName: original.seriesName,
                    seasonEpisodeLabel: original.seasonEpisodeLabel,
                    playbackProgress: original.playbackProgress,
                    imageURL: original.imageURL,
                    imageData: data
                )
            }
            return updatedItems
        }
    }

    // MARK: - DTO Mapping

    /// Maps a `BaseItemDto` from the Jellyfin API to a lightweight
    /// ``WidgetMediaItem`` suitable for widget rendering.
    private func mapToWidgetItem(
        _ dto: BaseItemDto,
        client: JellyfinAPIClient
    ) -> WidgetMediaItem? {
        guard let id = dto.id, let name = dto.name else { return nil }

        // Build season/episode label (e.g. "S2 E5")
        var seasonEpisodeLabel: String?
        if let season = dto.parentIndexNumber, let episode = dto.indexNumber {
            seasonEpisodeLabel = "S\(season) E\(episode)"
        }

        // Compute playback progress from position and runtime ticks
        var playbackProgress: Double?
        if let positionTicks = dto.userData?.playbackPositionTicks,
            let runtimeTicks = dto.runTimeTicks,
            runtimeTicks > 0
        {
            playbackProgress = Double(positionTicks) / Double(runtimeTicks)
        }

        // Use the existing API client to build the image URL
        let imageURL: URL? =
            if dto.imageTags?["Primary"] != nil {
                client.imageURL(itemId: id, imageType: "Primary", maxWidth: 300)
            } else {
                nil
            }

        return WidgetMediaItem(
            id: id,
            title: name,
            seriesName: dto.seriesName,
            seasonEpisodeLabel: seasonEpisodeLabel,
            playbackProgress: playbackProgress,
            imageURL: imageURL,
            imageData: nil
        )
    }
}
