import Models
import SwiftUI

// MARK: - Video Detail Scaffold

/// A reusable scaffold for video detail views (movies, series, etc.).
///
/// Renders the standard hero → metadata pills → overview → links → genres →
/// studios layout. The caller can inject additional content
/// (e.g. play button, season picker, episode list) via the `header` and `footer` slots.
///
/// When a `posterURL` is provided, the scaffold uses a cinematic composite hero
/// layout with a landscape backdrop and floating poster card. Otherwise it falls
/// back to the classic portrait hero with overlaid text.
struct VideoDetailScaffold<Header: View, Footer: View>: View {
    let item: MediaItem
    let displayItem: MediaItem
    let backdropURL: URL?
    let posterURL: URL?
    let heroSubtitleParts: [String]
    let showExternalLinks: Bool
    let overviewLineLimit: Int
    let overviewFont: Font
    let libraryId: ItemID?
    let isFavorite: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let footer: Footer

    init(
        item: MediaItem,
        displayItem: MediaItem,
        backdropURL: URL?,
        posterURL: URL? = nil,
        heroSubtitleParts: [String],
        showExternalLinks: Bool = true,
        overviewLineLimit: Int = 4,
        overviewFont: Font = .body,
        libraryId: ItemID? = nil,
        isFavorite: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.item = item
        self.displayItem = displayItem
        self.backdropURL = backdropURL
        self.posterURL = posterURL
        self.heroSubtitleParts = heroSubtitleParts
        self.showExternalLinks = showExternalLinks
        self.overviewLineLimit = overviewLineLimit
        self.overviewFont = overviewFont
        self.libraryId = libraryId
        self.isFavorite = isFavorite
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Hero Section

            if posterURL != nil {
                // Composite hero: landscape backdrop + floating poster + title
                CompositeHeroSection(
                    backdropURL: backdropURL,
                    posterURL: posterURL,
                    title: item.title,
                    originalTitle: displayItem.originalTitle,
                    subtitleParts: heroSubtitleParts,
                    tagline: displayItem.tagline,
                    isFavorite: isFavorite
                )
            } else {
                // Classic hero: portrait backdrop with overlaid text
                HeroSection(imageURL: backdropURL) {
                    VideoHeroOverlay(
                        title: item.title,
                        originalTitle: displayItem.originalTitle,
                        subtitleParts: heroSubtitleParts,
                        tagline: displayItem.tagline
                    )
                }
            }

            // MARK: - Header slot (e.g. play button)
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal)

                // Media info (ratings, technical specs, played status)
                MediaInfoSection(item: item, displayItem: displayItem)
                    .padding(.horizontal)

                // Overview
                if let overview = item.overview, !overview.isEmpty {
                    ExpandableOverview(
                        text: overview,
                        lineLimit: overviewLineLimit,
                        font: overviewFont
                    )
                    .padding(.horizontal)
                }

                // Enriched content — fades in once the detail fetch completes
                Group {
                    // External Links & Trailers
                    if showExternalLinks,
                        (displayItem.providerIds?.hasAny ?? false)
                            || !displayItem.remoteTrailerURLs.isEmpty
                    {
                        ExternalLinksSection(
                            providerIds: displayItem.providerIds,
                            mediaType: item.mediaType,
                            trailerURLs: displayItem.remoteTrailerURLs
                        )
                        .padding(.horizontal)
                    }

                    // Genres
                    if let genres = displayItem.genres ?? item.genres, !genres.isEmpty {
                        TappableChipFlowSection(
                            title: "Genres",
                            items: genres,
                            libraryId: libraryId
                        )
                        .padding(.horizontal)
                    }

                    // Studios
                    if let studios = displayItem.studios, !studios.isEmpty {
                        ChipFlowSection(title: "Studios", items: studios)
                            .padding(.horizontal)
                    }
                }
                .animation(.easeIn(duration: 0.3), value: displayItem.providerIds?.hasAny)
                .animation(.easeIn(duration: 0.3), value: displayItem.mediaStreams?.isEmpty)
                .animation(.easeIn(duration: 0.3), value: displayItem.genres)
                .animation(.easeIn(duration: 0.3), value: displayItem.studios)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            // MARK: - Footer slot (e.g. cast/crew, similar items, season picker)
            footer
        }
    }
}
