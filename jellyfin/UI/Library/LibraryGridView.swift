import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct LibraryGridView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("This library is empty.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            LibraryItemCard(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: library?.id) {
            await loadItems()
        }
    }

    private func loadItems() async {
        guard let library else {
            isLoading = false
            return
        }
        isLoading = true
        do {
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions()
            items = try await appState.provider.items(in: library, sort: sort, filter: filter)
        } catch {
            items = []
        }
        isLoading = false
    }
}
