import CoveUI
import SwiftUI

/// A convenience wrapper that renders a `CollectionLoader`'s phase with standard
/// loading / error / empty / content states.
///
/// Use this for simple views where the loading chrome is standard. For views that
/// need custom layout around the phase (e.g. a hero section above the loaded content),
/// switch on `loader.phase` directly instead.
///
/// ```swift
/// @State private var loader = CollectionLoader<Playlist>()
///
/// AsyncContentView(
///     loader,
///     loadingMessage: "Loading playlists…",
///     emptyTitle: "No Playlists",
///     emptySystemImage: "music.note.list",
///     emptyDescription: "You haven't created any playlists yet."
/// ) { playlists in
///     List(playlists) { playlist in
///         PlaylistRow(playlist: playlist)
///     }
/// }
/// .task {
///     await loader.load { try await provider.playlists() }
/// }
/// ```
struct AsyncContentView<Element: Sendable, Content: View>: View {

    // MARK: - Stored Properties

    private let loader: CollectionLoader<Element>
    private let loadingMessage: String
    private let errorTitle: String
    private let emptyTitle: String
    private let emptySystemImage: String
    private let emptyDescription: String?
    @ViewBuilder private let content: ([Element]) -> Content

    // MARK: - Init

    /// Creates an `AsyncContentView` that observes a `CollectionLoader` and renders
    /// the appropriate phase.
    ///
    /// - Parameters:
    ///   - loader: The `CollectionLoader` instance to observe (owned by the caller via `@State`).
    ///   - loadingMessage: Text shown alongside the spinner during the `.loading` phase.
    ///   - errorTitle: Title for the error state's `ContentUnavailableView`.
    ///   - emptyTitle: Title for the empty state's `ContentUnavailableView`.
    ///   - emptySystemImage: SF Symbol name for the empty state.
    ///   - emptyDescription: Optional description text for the empty state.
    ///   - content: A view builder that receives the loaded items.
    init(
        _ loader: CollectionLoader<Element>,
        loadingMessage: String = "Loading…",
        errorTitle: String = "Unable to Load",
        emptyTitle: String = "No Items",
        emptySystemImage: String = "tray",
        emptyDescription: String? = nil,
        @ViewBuilder content: @escaping ([Element]) -> Content
    ) {
        self.loader = loader
        self.loadingMessage = loadingMessage
        self.errorTitle = errorTitle
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyDescription = emptyDescription
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView(loadingMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                ContentUnavailableView(
                    errorTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )

            case .empty:
                if let emptyDescription {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptyDescription)
                    )
                } else {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage
                    )
                }

            case .loaded(let items):
                content(items)
            }
        }
    }
}
