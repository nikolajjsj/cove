import Defaults
import DownloadManager
import Foundation
import ImageService
import Models
import Observation
import Persistence
import os

/// Keeps every image the app can show on disk, so the catalogue is not just
/// browsable offline but looks the same offline.
///
/// Runs after each sync pass when "Keep all artwork on device" is on. Walks the
/// catalogue newest-first and fetches, through the shared pipeline, exactly the
/// requests the views make — same URL, same size, same cache key — in three
/// tiers so the most visible images land first:
///
/// 1. every card image (posters; episode thumbnails),
/// 2. the landscape backdrops Continue Watching uses,
/// 3. the full-width heroes: detail backdrops and episode stills.
///
/// Anything already stored is skipped, so a re-run after a delta costs one
/// directory check per image and one download per new or re-tagged image.
@Observable
@MainActor
final class ArtworkCache {
    enum Status: Equatable {
        case idle
        case running(done: Int, total: Int)
        case waitingForWiFi
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Bytes on disk, refreshed after each run and on request. Directory scan.
    private(set) var bytesOnDisk = 0
    /// When the last full run finished.
    private(set) var lastCompletedAt: Date?

    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Artwork")

    /// Builds the URL a view would build for the same item — the one code path,
    /// so the tag and size match. Set by `AppState`.
    var urlBuilder: ((MediaItem, ImageType, CGSize) -> URL?)?

    /// Fetches concurrently; the server resizes on demand, so be gentle.
    private let concurrency = 4

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    // MARK: - Entry points

    /// Run if the user asked for it. Cheap when nothing new landed.
    func runIfEnabled(repository: CatalogRepository, scope: CatalogRepository.Scope) {
        guard Defaults[.keepArtworkOffline] else { return }
        run(repository: repository, scope: scope)
    }

    func run(repository: CatalogRepository, scope: CatalogRepository.Scope) {
        guard !isRunning else { return }
        task?.cancel()
        task = Task { [weak self] in
            await self?.work(repository: repository, scope: scope)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { status = .idle }
    }

    func refreshUsage() async {
        bytesOnDisk = await Task.detached(priority: .utility) { ImageService.diskUsageBytes }.value
    }

    // MARK: - The walk

    private func work(repository: CatalogRepository, scope: CatalogRepository.Scope) async {
        guard let urlBuilder else { return }
        if !Defaults[.artworkOverCellular], NetworkMonitor.shared.isExpensive || NetworkMonitor.shared.isConstrained {
            status = .waitingForWiFi
            return
        }

        // The manifest: every URL, in tier order.
        var tiers: [[URL]] = [[], [], []]
        var offset = 0
        do {
            while true {
                let rows = try await repository.artworkRows(scope: scope, offset: offset, limit: 1_000)
                if rows.isEmpty { break }
                offset += rows.count
                for row in rows {
                    let (t1, t2, t3) = Self.urls(for: row, build: urlBuilder)
                    tiers[0] += t1
                    tiers[1] += t2
                    tiers[2] += t3
                }
                if Task.isCancelled { return }
            }
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        let all = tiers.flatMap { $0 }
        let total = all.count
        var done = 0
        var failed = 0
        status = .running(done: 0, total: total)
        logger.info("Artwork: \(total) images to check")

        // Hidden work runs at a priority that never competes with the screen.
        var iterator = all.makeIterator()
        await withTaskGroup(of: Bool.self) { group in
            func addNext() -> Bool {
                guard let url = iterator.next() else { return false }
                group.addTask(priority: .utility) { await ImageService.prefetch(url) }
                return true
            }
            for _ in 0..<concurrency where !addNext() { break }
            for await ok in group {
                done += 1
                if !ok { failed += 1 }
                if done % 25 == 0 || done == total { status = .running(done: done, total: total) }
                if Task.isCancelled { group.cancelAll(); break }
                _ = addNext()
            }
        }

        if Task.isCancelled {
            status = .idle
            return
        }
        logger.info("Artwork: \(done - failed) cached, \(failed) failed")
        lastCompletedAt = Date()
        status = failed > 0 && failed == total ? .failed("Couldn't reach the server for artwork.") : .idle
        await refreshUsage()
    }

    /// The three tiers for one item. Mirrors what the views ask for: see
    /// `MediaCard`, the detail heroes and `EpisodeDetailView`.
    private static func urls(
        for row: CatalogRepository.ArtworkRow,
        build: (MediaItem, ImageType, CGSize) -> URL?
    ) -> ([URL], [URL], [URL]) {
        let isEpisode = row.type == "Episode"
        let mediaType: MediaType = isEpisode ? .episode : (row.type == "Series" ? .series : .movie)
        let item = MediaItem(id: ItemID(row.itemId), title: "", mediaType: mediaType, imageTags: row.imageTags)
        var cards: [URL] = []
        var landscapes: [URL] = []
        var heroes: [URL] = []
        if isEpisode {
            // Episode rows and Up Next cards: the still, landscape.
            build(item, .primary, ArtworkSize.landscape).map { cards.append($0) }
            // The episode page hero: the same still, full width.
            build(item, .primary, ArtworkSize.backdrop).map { heroes.append($0) }
        } else {
            build(item, .primary, ArtworkSize.poster).map { cards.append($0) }
            if row.type != "Season" {
                build(item, .backdrop, ArtworkSize.landscape).map { landscapes.append($0) }
                build(item, .backdrop, ArtworkSize.backdrop).map { heroes.append($0) }
            }
        }
        return (cards, landscapes, heroes)
    }
}
