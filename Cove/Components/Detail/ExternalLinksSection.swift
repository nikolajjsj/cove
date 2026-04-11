import Models
import SwiftUI

/// A horizontal row of tappable external link buttons (IMDb, TMDB, TVDB).
struct ExternalLinksSection: View {
    let providerIds: ProviderIds
    let mediaType: MediaType

    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = buildLinks()
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("External Links")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach(links, id: \.label) { link in
                        Button {
                            openURL(link.url)
                        } label: {
                            Label(link.label, systemImage: link.icon)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(link.tint)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct ExternalLink {
        let icon: String
        let label: String
        let url: URL
        let tint: Color
    }

    private func buildLinks() -> [ExternalLink] {
        var links: [ExternalLink] = []

        if let url = providerIds.imdbURL {
            links.append(
                ExternalLink(
                    icon: "film",
                    label: "IMDb",
                    url: url,
                    tint: .yellow
                ))
        }

        if let url = providerIds.tmdbURL(for: mediaType) {
            links.append(
                ExternalLink(
                    icon: "film.stack",
                    label: "TMDB",
                    url: url,
                    tint: .cyan
                ))
        }

        if let url = providerIds.tvdbURL {
            // Only show TVDB for series
            if mediaType == .series {
                links.append(
                    ExternalLink(
                        icon: "tv",
                        label: "TVDB",
                        url: url,
                        tint: .green
                    ))
            }
        }

        return links
    }
}
