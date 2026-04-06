import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// Detail view showing a person's filmography.
///
/// Displays a circular portrait, name, type, and a grid of all media items
/// they appeared in. Each item navigates to its detail view.
struct PersonDetailView: View {
    let person: Person

    @Environment(AppState.self) private var appState
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading filmography…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        personHeader
                        filmographySection
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(person.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadFilmography()
        }
    }

    // MARK: - Header

    private var personHeader: some View {
        VStack(spacing: 16) {
            // Circular portrait
            LazyImage(url: person.imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay { ProgressView() }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            // Name
            Text(person.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Type (Actor, Director, etc.)
            if let type = person.type, !type.isEmpty {
                Text(type)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    // MARK: - Filmography

    @ViewBuilder
    private var filmographySection: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Items",
                systemImage: "film",
                description: Text("No filmography found for this person.")
            )
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filmography")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            LibraryItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Data Loading

    private func loadFilmography() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await appState.provider.personItems(personId: person.id)
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
        isLoading = false
    }
}
