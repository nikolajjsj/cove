import Models
import SwiftUI

/// A route value for navigating to the "See All" search results view.
struct SearchSeeAllRoute: Hashable {
    let query: String
    let mediaType: MediaType
    let title: String
}

struct SearchResultsSection: View {
    let title: String
    let items: [MediaItem]
    let mediaType: MediaType
    let query: String
    let maxItems: Int

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Header row with title and "See All" if there are more items than maxItems
                HStack {
                    Text(title)
                        .font(.title3)
                        .bold()

                    Spacer()

                    if items.count > maxItems {
                        NavigationLink(
                            value: SearchSeeAllRoute(
                                query: query,
                                mediaType: mediaType,
                                title: title
                            )
                        ) {
                            Text("See All")
                                .font(.subheadline)
                                .foregroundStyle(.accent)
                        }
                    }
                }
                .padding(.horizontal)

                // Item rows (limited to maxItems)
                LazyVStack(spacing: 0) {
                    ForEach(items.prefix(maxItems)) { item in
                        NavigationLink(value: item) {
                            SearchResultRow(item: item)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
