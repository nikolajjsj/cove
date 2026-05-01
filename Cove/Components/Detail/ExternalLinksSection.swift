import CoveUI
import Models
import SwiftUI

/// A wrapping row of tappable external link chips (IMDb, TMDB, TVDB)
/// and remote trailer chips ("TRAILER", "TRAILER 1", etc.).
struct ExternalLinksSection: View {
    let providerIds: ProviderIds?
    let mediaType: MediaType
    var trailerURLs: [URL] = []

    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = buildLinks()

        if !links.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(links, id: \.label) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Label(link.label, systemImage: link.icon)
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

    // MARK: - External Links

    private struct ExternalLink {
        let label: String
        let icon: String
        let url: URL
        let tint: Color
    }

    private func buildLinks() -> [ExternalLink] {
        var links: [ExternalLink] = []

        if let providerIds {
            if let url = providerIds.imdbURL {
                links.append(
                    ExternalLink(
                        label: "IMDb",
                        icon: "arrow.up.forward",
                        url: url,
                        tint: .yellow
                    ))
            }

            if let url = providerIds.tmdbURL(for: mediaType) {
                links.append(
                    ExternalLink(
                        label: "TMDB",
                        icon: "arrow.up.forward",
                        url: url,
                        tint: .cyan
                    ))
            }

            if let url = providerIds.tvdbURL {
                if mediaType == .series {
                    links.append(
                        ExternalLink(
                            label: "TVDB",
                            icon: "arrow.up.forward",
                            url: url,
                            tint: .green
                        ))
                }
            }
        }

        if trailerURLs.count == 1 {
            links.append(
                ExternalLink(label: "TRAILER", icon: "film", url: trailerURLs[0], tint: .orange)
            )
        } else {
            for (index, url) in trailerURLs.enumerated() {
                links.append(
                    ExternalLink(
                        label: "TRAILER \(index + 1)",
                        icon: "film",
                        url: url,
                        tint: .orange
                    )
                )
            }
        }

        return links
    }
}
