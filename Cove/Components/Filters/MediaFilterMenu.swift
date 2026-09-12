import SwiftUI

/// The single toolbar control for every media filter.
///
/// Replaces the row of always-visible chips. Inactive filters now cost no
/// vertical space at all, and the toolbar glyph fills to signal that something
/// is applied — the pattern Files, Photos, and Mail use.
struct MediaFilterMenu: View {
    var selection: MediaFilterSelection

    var body: some View {
        Menu {
            Section("Watched") {
                Picker("Watched", selection: selection.$watched) {
                    ForEach(WatchedFilter.allCases, id: \.self) { filter in
                        Label(filter.label, systemImage: filter.systemImage).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Toggle(isOn: selection.$favoritesOnly) {
                    Label("Favorites Only", systemImage: "heart")
                }
            }

            if selection.includesVideoFilters {
                if !selection.availableGenres.isEmpty {
                    Section("Genre") {
                        Menu {
                            ForEach(selection.availableGenres, id: \.self) { genre in
                                Toggle(genre, isOn: genreBinding(genre))
                            }
                        } label: {
                            Label(genreLabel, systemImage: "tag")
                        }
                    }
                }

                Section("Release Decade") {
                    Picker("Release Decade", selection: selection.$decade) {
                        Text("Any Decade").tag(Decade?.none)
                        ForEach(Decade.allCases, id: \.self) { decade in
                            Text(decade.rawValue).tag(Decade?.some(decade))
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Minimum Rating") {
                    Picker("Minimum Rating", selection: selection.$minRating) {
                        Text("Any Rating").tag(Double?.none)
                        ForEach([6.0, 7.0, 8.0, 9.0], id: \.self) { rating in
                            Text("\(Int(rating))+").tag(Double?.some(rating))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            if selection.isActive {
                Section {
                    Button("Clear Filters", systemImage: "arrow.uturn.backward", role: .destructive) {
                        selection.clear()
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: glyph)
        }
        // Keep the menu open while several filters are set in one go, the way
        // Photos does — otherwise each choice costs another tap to reopen.
        .menuActionDismissBehavior(.disabled)
        .tint(selection.isActive ? .accentColor : nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private var glyph: String {
        selection.isActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private var genreLabel: String {
        switch selection.genres.count {
        case 0: "Any Genre"
        case 1: selection.genres.first ?? "Any Genre"
        default: "\(selection.genres.count) Genres"
        }
    }

    private var accessibilityLabel: String {
        let count = selection.active.count
        return count == 0 ? "Filter" : "Filter, \(count) active"
    }

    private func genreBinding(_ genre: String) -> Binding<Bool> {
        Binding(
            get: { selection.genres.contains(genre) },
            set: { isOn in
                if isOn {
                    selection.genres.insert(genre)
                } else {
                    selection.genres.remove(genre)
                }
            }
        )
    }
}
