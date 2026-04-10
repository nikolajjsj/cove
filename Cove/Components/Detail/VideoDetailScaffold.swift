import CoveUI
import Models
import SwiftUI

// MARK: - Video Detail Scaffold

/// A reusable scaffold for video detail views (movies, series, etc.).
///
/// Renders the standard hero → metadata pills → overview → links → genres →
/// studios layout. The caller can inject additional content
/// (e.g. play button, season picker, episode list) via the `header` and `footer` slots.
struct VideoDetailScaffold<Header: View, Footer: View>: View {
    let item: MediaItem
    let displayItem: MediaItem
    let backdropURL: URL?
    let heroSubtitleParts: [String]
    let metadataPills: [MetadataPill]
    let showExternalLinks: Bool
    let overviewLineLimit: Int
    let overviewFont: Font
    let overviewExpandThreshold: Int?
    let libraryId: ItemID?
    @ViewBuilder let header: Header
    @ViewBuilder let footer: Footer

    init(
        item: MediaItem,
        displayItem: MediaItem,
        backdropURL: URL?,
        heroSubtitleParts: [String],
        metadataPills: [MetadataPill],
        showExternalLinks: Bool = true,
        overviewLineLimit: Int = 4,
        overviewFont: Font = .body,
        overviewExpandThreshold: Int? = nil,
        libraryId: ItemID? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.item = item
        self.displayItem = displayItem
        self.backdropURL = backdropURL
        self.heroSubtitleParts = heroSubtitleParts
        self.metadataPills = metadataPills
        self.showExternalLinks = showExternalLinks
        self.overviewLineLimit = overviewLineLimit
        self.overviewFont = overviewFont
        self.overviewExpandThreshold = overviewExpandThreshold
        self.libraryId = libraryId
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Hero Backdrop
            HeroSection(imageURL: backdropURL) {
                VideoHeroOverlay(
                    title: item.title,
                    originalTitle: displayItem.originalTitle,
                    subtitleParts: heroSubtitleParts,
                    tagline: displayItem.tagline
                )
            }

            // MARK: - Header slot (e.g. play button)
            VStack(alignment: .leading, spacing: 16) {
                header

                // Metadata pills
                MetadataPillsView(metadataPills)

                // Overview
                if let overview = item.overview, !overview.isEmpty {
                    ExpandableOverview(
                        text: overview,
                        lineLimit: overviewLineLimit,
                        font: overviewFont,
                        expandThreshold: overviewExpandThreshold
                    )
                }

                // External Links
                if showExternalLinks,
                    let providerIds = displayItem.providerIds,
                    providerIds.hasAny
                {
                    ExternalLinksSection(
                        providerIds: providerIds,
                        mediaType: item.mediaType
                    )
                }

                // Genres
                if let genres = displayItem.genres ?? item.genres, !genres.isEmpty {
                    TappableChipFlowSection(
                        title: "Genres",
                        items: genres,
                        libraryId: libraryId
                    )
                }

                // Studios
                if let studios = displayItem.studios, !studios.isEmpty {
                    ChipFlowSection(title: "Studios", items: studios)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // MARK: - Footer slot (e.g. cast/crew, similar items, season picker)
            footer
        }
    }
}
