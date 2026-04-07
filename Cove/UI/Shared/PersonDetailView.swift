import CoveUI
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

    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    private let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 16)
    ]

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
            await loader.load {
                try await authManager.provider.personItems(personId: person.id)
            }
        }
    }

    // MARK: - Header

    private var personHeader: some View {
        VStack(spacing: 16) {
            // Circular portrait
            MediaImage(
                url: person.imageURL,
                placeholderIcon: "person.fill",
                placeholderIconFont: .system(size: 48),
                cornerRadius: .infinity
            )
            .frame(width: 200, height: 200)
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
        if loader.items.isEmpty {
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
                    ForEach(loader.items) { item in
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
}
