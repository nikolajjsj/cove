import OpenSubtitlesAPI
import SwiftUI

/// A sheet for searching and downloading subtitles from OpenSubtitles.
///
/// Presented from the video player's subtitle picker with a `.medium` detent.
/// Shows a language picker at the top and search results below.
struct SubtitleSearchSheet: View {
    @Bindable var viewModel: SubtitleSearchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isSearching {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.results.isEmpty {
                    SubtitleSearchErrorView(
                        error: error,
                        onRetry: {
                            Task { await viewModel.search() }
                        })
                } else if viewModel.results.isEmpty && !viewModel.isSearching {
                    ContentUnavailableView(
                        "Search for Subtitles",
                        systemImage: "captions.bubble",
                        description: Text("Select a language to search for subtitles.")
                    )
                } else {
                    SubtitleResultsList(
                        results: viewModel.results,
                        isDownloading: viewModel.isDownloading,
                        onSelect: { result in
                            Task {
                                await viewModel.download(result)
                                if viewModel.downloadSuccess {
                                    dismiss()
                                }
                            }
                        }
                    )
                }
            }
            .navigationTitle("Search Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    SubtitleLanguagePicker(
                        selectedLanguage: $viewModel.selectedLanguage,
                        preferredLanguages: viewModel.preferredLanguages,
                        displayName: viewModel.displayName(for:)
                    )
                }
            }
            .task {
                await viewModel.search()
            }
        }
    }
}

// MARK: - Language Picker

/// Compact language picker shown in the navigation bar.
private struct SubtitleLanguagePicker: View {
    @Binding var selectedLanguage: String
    let preferredLanguages: [String]
    let displayName: (String) -> String

    /// All ISO 639-1 language codes supported by OpenSubtitles.
    private var allLanguages: [String] {
        let all = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
        return all.sorted { displayName($0) < displayName($1) }
    }

    var body: some View {
        Menu {
            // Preferred languages section
            if !preferredLanguages.isEmpty {
                Section("Preferred") {
                    ForEach(preferredLanguages, id: \.self) { code in
                        Button {
                            selectedLanguage = code
                        } label: {
                            HStack {
                                Text(displayName(code))
                                if code == selectedLanguage {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            // All languages section
            Section("All Languages") {
                ForEach(allLanguages.filter { !preferredLanguages.contains($0) }, id: \.self) {
                    code in
                    Button {
                        selectedLanguage = code
                    } label: {
                        HStack {
                            Text(displayName(code))
                            if code == selectedLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(displayName(selectedLanguage))
                    .font(.subheadline)
                    .bold()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .bold()
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Results List

/// Scrollable list of subtitle search results.
private struct SubtitleResultsList: View {
    let results: [SubtitleResult]
    let isDownloading: Bool
    let onSelect: (SubtitleResult) -> Void

    var body: some View {
        List {
            ForEach(results) { result in
                SubtitleResultRow(
                    result: result,
                    isDownloading: isDownloading,
                    onSelect: { onSelect(result) }
                )
            }
        }
        .listStyle(.plain)
        .overlay {
            if isDownloading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Downloading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Result Row

/// A single subtitle search result row.
private struct SubtitleResultRow: View {
    let result: SubtitleResult
    let isDownloading: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.attributes.release)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Label(
                        result.attributes.downloadCount.formatted(.number),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if result.attributes.hearingImpaired {
                        Text("HI")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(.rect(cornerRadius: 4))
                    }

                    if let fileName = result.attributes.files.first?.fileName {
                        let ext = (fileName as NSString).pathExtension.uppercased()
                        if !ext.isEmpty {
                            Text(ext)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(isDownloading)
    }
}

// MARK: - Error View

/// Inline error view shown when search or download fails.
private struct SubtitleSearchErrorView: View {
    let error: SubtitleSearchError
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            if case .noResults = error {
                // No retry for "no results" — user should change language
            } else {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
