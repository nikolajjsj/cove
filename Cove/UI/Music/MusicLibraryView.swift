import Models
import SwiftUI

struct MusicLibraryView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var selectedSection: MusicSection = .artists
    @State private var sortField: SortField = .name
    @State private var sortOrder: Models.SortOrder = .ascending
    @State private var isFavoriteFilter = false

    enum MusicSection: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case genres = "Genres"

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Discovery shelves (fixed at top, shared across all sections)
            if let library {
                DiscoveryShelvesSection(library: library)
            }

            // Filter chips
            filterChips

            // Segmented picker
            Picker("Section", selection: $selectedSection) {
                ForEach(MusicSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Section content
            sectionContent
        }
        .navigationTitle("Music")
        .toolbar {
            if selectedSection != .genres {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
        .onChange(of: selectedSection) { _, _ in
            sortField = .name
            sortOrder = .ascending
        }
    }

    // MARK: - Sort Options Per Section

    private var availableSortFields: [(field: SortField, label: String)] {
        switch selectedSection {
        case .artists:
            return [
                (.name, "Name"),
                (.dateAdded, "Date Added"),
            ]
        case .albums:
            return [
                (.name, "Name"),
                (.dateAdded, "Date Added"),
                (.albumArtist, "Artist"),
                (.premiereDate, "Year"),
            ]
        case .songs:
            return [
                (.name, "Name"),
                (.dateAdded, "Date Added"),
                (.albumArtist, "Artist"),
                (.album, "Album"),
            ]
        case .playlists:
            return [
                (.name, "Name"),
                (.dateAdded, "Date Added"),
            ]
        case .genres:
            return [
                (.name, "Name")
            ]
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(availableSortFields, id: \.field) { option in
                Button {
                    if sortField == option.field {
                        sortOrder = sortOrder == .ascending ? .descending : .ascending
                    } else {
                        sortField = option.field
                        sortOrder = .ascending
                    }
                } label: {
                    HStack {
                        Text(option.label)
                        if sortField == option.field {
                            Spacer()
                            Image(
                                systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "Favorites",
                    icon: "heart.fill",
                    isActive: isFavoriteFilter
                ) {
                    isFavoriteFilter.toggle()
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .artists:
            ArtistListView(
                library: library, sortField: sortField, sortOrder: sortOrder,
                isFavoriteFilter: isFavoriteFilter)
        case .albums:
            AlbumListView(
                library: library, sortField: sortField, sortOrder: sortOrder,
                isFavoriteFilter: isFavoriteFilter)
        case .songs:
            SongListView(
                library: library, sortField: sortField, sortOrder: sortOrder,
                isFavoriteFilter: isFavoriteFilter)
        case .playlists:
            PlaylistListView(
                sortField: sortField, sortOrder: sortOrder, isFavoriteFilter: isFavoriteFilter)
        case .genres:
            GenreListView(library: library)
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor : Color(.secondarySystemFill))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Discovery Shelves Section

/// Hosts the three discovery shelves in a fixed-height horizontal scroll area.
/// Extracted as a separate view so SwiftUI preserves its identity (and loaded data)
/// across picker-selection changes.
private struct DiscoveryShelvesSection: View {
    let library: MediaLibrary

    var body: some View {
        VStack(spacing: 12) {
            MusicDiscoveryShelf(
                title: "Recently Added",
                sortField: .dateCreated,
                library: library
            )

            MusicDiscoveryShelf(
                title: "Most Played",
                sortField: .playCount,
                library: library
            )

            MusicDiscoveryShelf(
                title: "Recently Played",
                sortField: .datePlayed,
                library: library
            )
        }
        .padding(.vertical, 4)
        .frame(maxHeight: 240)
        .clipped()
    }
}

#Preview {
    NavigationStack {
        MusicLibraryView(library: nil)
            .environment(AppState())
    }
}
