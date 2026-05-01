import Models
import SwiftUI

/// A horizontal scroll rail showing cast & crew members with circular portraits.
///
/// Tapping a person navigates to their filmography via `NavigationLink(value: person)`.
struct CastCrewRail: View {
    let people: [Person]

    var body: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cast & Crew")
                    .font(.title3)
                    .bold()
                    .padding(.horizontal)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(people, id: \.uniqueID) { person in
                            NavigationLink(value: person) {
                                PersonCard(person: person)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Person Card

private struct PersonCard: View {
    let person: Person

    var body: some View {
        VStack(spacing: 8) {
            // Circular portrait
            MediaImage(
                url: person.imageURL,
                placeholderIcon: "person.fill",
                placeholderIconFont: .title3,
                cornerRadius: .infinity,
                showsLoadingIndicator: false
            )
            .frame(width: 80, height: 80)

            VStack {
                // Name
                Text(person.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // Role or type
                if let label = person.role.flatMap({ $0.isEmpty ? nil : $0 })
                    ?? person.type.flatMap({ $0.isEmpty ? nil : $0 })
                {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 80)
    }
}
