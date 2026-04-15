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
            HStack(spacing: 8) {
                ForEach(links, id: \.label) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Label(link.label, systemImage: "arrow.up.forward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(link.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(link.tint.opacity(0.15), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct ExternalLink {
        let label: String
        let url: URL
        let tint: Color
    }

    private func buildLinks() -> [ExternalLink] {
        var links: [ExternalLink] = []

        if let url = providerIds.imdbURL {
            links.append(
                ExternalLink(
                    label: "IMDb",
                    url: url,
                    tint: .yellow
                ))
        }

        if let url = providerIds.tmdbURL(for: mediaType) {
            links.append(
                ExternalLink(
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
                        label: "TVDB",
                        url: url,
                        tint: .green
                    ))
            }
        }

        return links
    }
}
