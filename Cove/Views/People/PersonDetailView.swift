import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// Detail view showing a person's filmography.
///
/// Displays a circular portrait, name, type, and filmography items
/// grouped by media type (Movies, TV Shows, Episodes, etc.) so each
/// category is visually distinct.
struct PersonDetailView: View {
    let person: Person

    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView("Loading filmography…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .empty, .loaded:
                ScrollView {
                    VStack(spacing: 24) {
                        PersonHeaderView(person: person)
                        PersonFilmographySection(items: loader.items)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(person.name)
        .inlineNavigationTitle()
        .task {
            await loader.load {
                try await authManager.provider.personItems(personId: person.id)
            }
        }
    }
}

// MARK: - Person Header

private struct PersonHeaderView: View {
    let person: Person

    var body: some View {
        VStack(spacing: 16) {
            MediaImage(
                url: person.imageURL,
                placeholderIcon: "person.fill",
                placeholderIconFont: .system(size: 48),
                cornerRadius: .infinity
            )
            .frame(width: 200, height: 200)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Text(person.name)
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)

            if let type = person.type, !type.isEmpty {
                Text(type)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }
}

// MARK: - Filmography Section

private struct PersonFilmographySection: View {
    let items: [MediaItem]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Items",
                systemImage: "film",
                description: Text("No filmography found for this person.")
            )
            .padding(.top, 24)
        } else {
            let grouped = groupedFilmography
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(grouped, id: \.category) { section in
                    FilmographySectionView(section: section)
                }
            }
        }
    }

    private var groupedFilmography: [FilmographySection] {
        let grouped = Dictionary(grouping: items) {
            FilmographyCategory(mediaType: $0.mediaType)
        }

        return FilmographyCategory.displayOrder.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }

            let sorted = items.sorted { lhs, rhs in
                // Sort by year descending, then title ascending
                let lhsYear = lhs.productionYear ?? 0
                let rhsYear = rhs.productionYear ?? 0
                if lhsYear != rhsYear { return lhsYear > rhsYear }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return FilmographySection(category: category, items: sorted)
        }
    }
}

// MARK: - Filmography Section View

private struct FilmographySectionView: View {
    let section: FilmographySection

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 8) {
                Text(section.category.displayTitle)
                    .font(.title2)
                    .bold()

                Text("\(section.items.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal)

            // Items list
            LazyVStack(spacing: 0) {
                ForEach(section.items.enumerated(), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        FilmographyRowView(item: item, imageURL: posterURL(for: item))
                    }
                    .buttonStyle(.plain)

                    if index < section.items.count - 1 {
                        Divider()
                            .padding(.leading, 92)
                            .padding(.horizontal)
                    }
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func posterURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 150, height: 225)
        )
    }
}

// MARK: - Filmography Row

private struct FilmographyRowView: View {
    let item: MediaItem
    let imageURL: URL?

    @Environment(UserDataStore.self) private var userDataStore

    var body: some View {
        MediaItemRow(
            imageURL: imageURL,
            title: item.title,
            subtitle: subtitle,
            mediaType: item.mediaType,
            metadata: metadataParts,
            isPlayed: userDataStore.isPlayed(item.id, fallback: item.userData),
        ) {
            RatingBadge(rating: item.communityRating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var subtitle: String? {
        switch item.mediaType {
        case .episode:
            var parts: [String] = []
            if let seriesName = item.seriesName {
                parts.append(seriesName)
            }
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                parts.append("S\(season)E\(episode)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .series:
            if let year = item.productionYear {
                if let endDate = item.endDate {
                    let endYear = Calendar.current.component(.year, from: endDate)
                    return endYear != year ? "\(year)–\(endYear)" : "\(year)"
                }
                return "\(year)–Present"
            }
            return nil
        default:
            return nil
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []

        if item.mediaType != .series, let year = item.productionYear {
            parts.append("\(year)")
        }

        if let officialRating = item.officialRating, !officialRating.isEmpty {
            parts.append(officialRating)
        }

        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        return parts
    }
}

// MARK: - Filmography Category

private enum FilmographyCategory: Hashable {
    case movies
    case series
    case episodes
    case music
    case other

    init(mediaType: MediaType) {
        switch mediaType {
        case .movie:
            self = .movies
        case .series:
            self = .series
        case .episode:
            self = .episodes
        case .album, .track, .artist, .playlist:
            self = .music
        default:
            self = .other
        }
    }

    static let displayOrder: [FilmographyCategory] = [
        .movies, .series, .episodes, .music, .other,
    ]

    var displayTitle: String {
        switch self {
        case .movies: "Movies"
        case .series: "TV Shows"
        case .episodes: "Episodes"
        case .music: "Music"
        case .other: "Other"
        }
    }
}

// MARK: - Filmography Section

private struct FilmographySection {
    let category: FilmographyCategory
    let items: [MediaItem]
}
