import Models
import SwiftUI

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
                        .fontWeight(.bold)

                    Spacer()

                    if items.count > maxItems {
                        NavigationLink {
                            SearchSeeAllView(
                                query: query,
                                mediaType: mediaType,
                                title: title
                            )
                        } label: {
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
