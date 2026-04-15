import Models
import SwiftUI

/// A horizontal row of tappable external link chips (IMDb, TMDB, TVDB)
/// and remote trailer chips ("TRAILER", "TRAILER 1", etc.).
struct ExternalLinksSection: View {
    let providerIds: ProviderIds?
    let mediaType: MediaType
    var trailerURLs: [URL] = []

    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = buildLinks()
        let trailers = buildTrailerLinks()

        if !links.isEmpty || !trailers.isEmpty {
            HStack(spacing: 8) {
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

                ForEach(trailers, id: \.label) { trailer in
                    Button {
                        openURL(trailer.url)
                    } label: {
                        Label(trailer.label, systemImage: "film")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.15), in: .capsule)
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
        guard let providerIds else { return [] }
        var links: [ExternalLink] = []

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

        return links
    }

    // MARK: - Trailer Links

    private struct TrailerLink {
        let label: String
        let url: URL
    }

    private func buildTrailerLinks() -> [TrailerLink] {
        guard !trailerURLs.isEmpty else { return [] }

        if trailerURLs.count == 1 {
            return [TrailerLink(label: "TRAILER", url: trailerURLs[0])]
        }

        return trailerURLs.enumerated().map { index, url in
            TrailerLink(label: "TRAILER \(index + 1)", url: url)
        }
    }
}
