import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No libraries found on this server.")
                    )
                } else {
                    ContinueWatchingSection()
                    UpNextSection()
                    ForEach(appState.libraries) { library in
                        LibrarySection(library: library)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Continue Watching Section

private struct ContinueWatchingSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var resumeItems: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Continue Watching")

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonCard.landscape(width: 240)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else if !resumeItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Continue Watching")

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(resumeItems) { item in
                                NavigationLink(value: item) {
                                    ContinueWatchingCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: resumeItems.map(\.id))
        .task {
            await loadResumeItems()
        }
    }

    private func loadResumeItems() async {
        let firstLoad = resumeItems.isEmpty
        if firstLoad { isLoading = true }
        defer { if firstLoad { isLoading = false } }
        do {
            resumeItems = try await authManager.provider.resumeItems()
        } catch {
            resumeItems = []
        }
    }
}

// MARK: - Up Next Section

private struct UpNextSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var nextUpItems: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Up Next")

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonCard.landscape(width: 240)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else if !nextUpItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Up Next")

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(nextUpItems) { item in
                                NavigationLink(value: item) {
                                    UpNextCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: nextUpItems.map(\.id))
        .task {
            await loadNextUp()
        }
    }

    private func loadNextUp() async {
        let firstLoad = nextUpItems.isEmpty
        if firstLoad { isLoading = true }
        defer { if firstLoad { isLoading = false } }
        do {
            nextUpItems = try await authManager.provider.nextUp()
        } catch {
            nextUpItems = []
        }
    }
}

// MARK: - Library Section (horizontal scroll of recent items)

private struct LibrarySection: View {
    let library: MediaLibrary
    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: library) {
                HStack {
                    Text(library.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !isLoading && items.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        if isLoading {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonCard(
                                    width: defaultCardWidth,
                                    aspectRatio: defaultAspectRatio,
                                    lineCount: 2
                                )
                            }
                        } else {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    LibraryItemCard(item: item)
                                        .frame(width: cardWidth(for: item))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        let firstVisit = items.isEmpty

        if firstVisit { isLoading = true }
        defer { if firstVisit { isLoading = false } }
        do {
            let sort = SortOptions(field: .dateAdded, order: .descending)
            let filter = FilterOptions(
                limit: 20,
                includeItemTypes: library.includeItemTypes
            )
            items = try await authManager.provider.items(in: library, sort: sort, filter: filter)
        } catch {
            items = []
        }
    }

    private var isMusic: Bool {
        library.collectionType == .music
    }

    private var defaultCardWidth: CGFloat {
        isMusic ? 140 : 130
    }

    private var defaultAspectRatio: CGFloat {
        isMusic ? 1.0 : 2.0 / 3.0
    }

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist:
            140  // Square cards for music
        default:
            130  // Portrait cards for video
        }
    }
}
