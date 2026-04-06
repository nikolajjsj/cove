import ImageService
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
                    .fontWeight(.bold)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(people, id: \.uniqueID) { person in
                            NavigationLink(value: person) {
                                PersonCard(person: person)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
            LazyImage(url: person.imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            VStack {
                // Name
                Text(person.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                // Role
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let type = person.type, !type.isEmpty {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 80)
    }
}
