import Defaults
import Foundation
import JellyfinProvider
import Keychain
import Models
import OpenSubtitlesAPI
import PlaybackEngine
import os

/// Orchestrates the subtitle search, download, upload, and activation flow.
///
/// Coordinates between `OpenSubtitlesClient` (search + download),
/// `JellyfinServerProvider` (upload to server), and `VideoPlaybackManager`
/// (activate the new subtitle track during playback).
@Observable
@MainActor
final class SubtitleSearchViewModel {

    // MARK: - Configuration

    let item: MediaItem
    let streamInfo: StreamInfo
    let provider: JellyfinServerProvider
    let videoManager: VideoPlaybackManager

    // MARK: - State

    private(set) var results: [SubtitleResult] = []
    private(set) var isSearching = false
    private(set) var isDownloading = false
    private(set) var error: SubtitleSearchError?
    private(set) var downloadSuccess = false

    /// The currently selected language code (ISO 639-1).
    var selectedLanguage: String {
        didSet {
            if oldValue != selectedLanguage {
                Task { await search() }
            }
        }
    }

    // MARK: - Private

    private let logger = Logger(
        subsystem: "com.nikolajjsj.cove", category: "SubtitleSearch")
    private let keychain = KeychainService()

    private static let apiKeyAccount = "opensubtitles-api-key"

    // MARK: - Init

    init(
        item: MediaItem,
        streamInfo: StreamInfo,
        provider: JellyfinServerProvider,
        videoManager: VideoPlaybackManager
    ) {
        self.item = item
        self.streamInfo = streamInfo
        self.provider = provider
        self.videoManager = videoManager

        // Determine initial language: last used, or device primary
        let recentLanguages = Defaults[.openSubtitlesRecentLanguages]
        if let lastUsed = recentLanguages.first {
            self.selectedLanguage = lastUsed
        } else {
            let deviceLanguage =
                Locale.preferredLanguages.first
                .flatMap { Locale(identifier: $0).language.languageCode?.identifier }
                ?? "en"
            self.selectedLanguage = deviceLanguage
        }
    }

    // MARK: - Language Helpers

    /// Languages pinned to the top of the picker: user's recent languages
    /// merged with device-preferred languages, deduplicated and ordered.
    var preferredLanguages: [String] {
        var seen = Set<String>()
        var result: [String] = []

        // Recent languages first (most recent at top)
        for lang in Defaults[.openSubtitlesRecentLanguages] {
            if seen.insert(lang).inserted {
                result.append(lang)
            }
        }

        // Then device-preferred languages
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? preferred
            if seen.insert(code).inserted {
                result.append(code)
            }
        }

        return result
    }

    /// Localized display name for a language code.
    func displayName(for languageCode: String) -> String {
        Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode.uppercased()
    }

    // MARK: - Search

    /// Search OpenSubtitles for subtitles matching the current item and language.
    func search() async {
        guard !isSearching else { return }

        isSearching = true
        error = nil
        results = []
        defer { isSearching = false }

        guard let apiKey = keychain.token(forServerID: Self.apiKeyAccount), !apiKey.isEmpty else {
            error = .apiKeyRequired
            return
        }

        let client = OpenSubtitlesClient(apiKey: apiKey)

        do {
            let imdbId = item.providerIds?.imdb
            let query: String? = imdbId == nil ? buildSearchQuery() : nil

            let response = try await client.search(
                imdbId: imdbId,
                query: query,
                language: selectedLanguage
            )

            results = response.data
        } catch let osError as OpenSubtitlesError {
            error = mapError(osError)
        } catch is DecodingError {
            logger.error("Failed to decode OpenSubtitles response")
            self.error = .networkError(
                description: "Unexpected response format from OpenSubtitles.")
        } catch {
            self.error = .networkError(description: error.localizedDescription)
        }
    }

    // MARK: - Download + Upload + Activate

    /// Download a subtitle from OpenSubtitles, upload it to Jellyfin, and activate it.
    ///
    /// - Parameter result: The selected subtitle search result.
    func download(_ result: SubtitleResult) async {
        guard let file = result.attributes.files.first else {
            error = .downloadFailed
            return
        }

        isDownloading = true
        error = nil
        downloadSuccess = false
        defer { isDownloading = false }

        guard let apiKey = keychain.token(forServerID: Self.apiKeyAccount), !apiKey.isEmpty else {
            error = .apiKeyRequired
            return
        }

        let client = OpenSubtitlesClient(apiKey: apiKey)

        do {
            // Step 1: Get download link from OpenSubtitles
            logger.info("Requesting download link for file \(file.fileId)")
            let downloadResponse = try await client.downloadLink(fileId: file.fileId)

            // Step 2: Download the actual subtitle file
            logger.info("Downloading subtitle from \(downloadResponse.link)")
            let subtitleData = try await client.downloadSubtitleData(from: downloadResponse.link)

            // Step 3: Determine format from filename
            let format = subtitleFormat(from: file.fileName)

            // Step 4: Convert language code from ISO 639-1 to ISO 639-2 for Jellyfin
            let jellyfinLanguage = iso639_2Code(from: result.attributes.language)

            // Step 5: Upload to Jellyfin server
            logger.info(
                "Uploading subtitle to Jellyfin server (format: \(format), language: \(jellyfinLanguage))"
            )
            do {
                try await provider.uploadSubtitle(
                    itemId: item.id,
                    language: jellyfinLanguage,
                    format: format,
                    data: subtitleData
                )
                logger.info("Subtitle uploaded successfully")
            } catch {
                // Upload failed — fall back to local playback
                logger.warning(
                    "Jellyfin upload failed: \(error.localizedDescription). Falling back to local subtitle."
                )
                ToastManager.shared.show(
                    "Subtitle saved locally (server upload failed)",
                    icon: "exclamationmark.triangle.fill",
                    style: .info
                )
                activateLocalSubtitle(
                    data: subtitleData, format: format, language: result.attributes.language)
                recordLanguageUsage(result.attributes.language)
                downloadSuccess = true
                return
            }

            // Step 6: Optimistically activate the new subtitle
            activateUploadedSubtitle(language: result.attributes.language)

            // Step 7: Record language usage
            recordLanguageUsage(result.attributes.language)

            downloadSuccess = true
            logger.info("Subtitle activated successfully")

        } catch let osError as OpenSubtitlesError {
            error = mapError(osError)
        } catch {
            self.error = .downloadFailed
        }
    }

    // MARK: - API Key

    /// Whether an OpenSubtitles API key is configured.
    var hasApiKey: Bool {
        keychain.token(forServerID: Self.apiKeyAccount) != nil
    }

    /// Store an OpenSubtitles API key in the Keychain.
    static func setApiKey(_ key: String?) {
        let keychain = KeychainService()
        if let key, !key.isEmpty {
            try? keychain.setToken(key, forServerID: apiKeyAccount)
        } else {
            keychain.deleteToken(forServerID: apiKeyAccount)
        }
    }

    /// Read the currently stored OpenSubtitles API key.
    static func getApiKey() -> String? {
        KeychainService().token(forServerID: apiKeyAccount)
    }

    // MARK: - Private Helpers

    /// Build a fallback search query from item title and year.
    private func buildSearchQuery() -> String {
        var query = item.title
        if let year = item.productionYear {
            query += " \(year)"
        }
        return query
    }

    /// Extract subtitle format from a filename (defaults to "srt").
    private func subtitleFormat(from fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "srt" : ext
    }

    /// Convert ISO 639-1 (2-letter) to ISO 639-2/B (3-letter) code for Jellyfin.
    /// Falls back to the input if no mapping exists.
    private func iso639_2Code(from iso639_1: String) -> String {
        // Use Foundation's Locale to convert
        let locale = Locale(identifier: iso639_1)
        // Try to get the 3-letter code
        if locale.language.languageCode != nil {
            // Locale.Language.LanguageCode doesn't directly give us ISO 639-2,
            // but we can use a known mapping for common languages.
            return Self.languageCodeMap[iso639_1] ?? iso639_1
        }
        return iso639_1
    }

    /// Activate a subtitle by feeding the raw data as a local external subtitle.
    /// Used as fallback when Jellyfin upload fails.
    private func activateLocalSubtitle(data: Data, format: String, language: String) {
        // Write to a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "opensubtitles_\(language).\(format)"
        let fileURL = tempDir.appending(path: fileName)

        do {
            try data.write(to: fileURL)

            // Create a new subtitle track and activate it
            let newIndex = (videoManager.subtitleTracks.map(\.id).max() ?? -1) + 1
            let track = SubtitleTrack(
                id: newIndex,
                title: displayName(for: language),
                language: language,
                isExternal: true,
                url: fileURL
            )
            videoManager.appendSubtitleTrack(track)
            videoManager.selectSubtitle(at: newIndex, externalURL: fileURL)
        } catch {
            logger.error("Failed to write temporary subtitle file: \(error.localizedDescription)")
        }
    }

    /// Optimistically activate an uploaded subtitle track.
    /// Builds a new `SubtitleTrack` and selects it via the server URL.
    private func activateUploadedSubtitle(language: String) {
        // The new subtitle gets the next available index.
        // We approximate this from the existing tracks.
        let existingMaxIndex = videoManager.subtitleTracks.map(\.id).max() ?? -1
        let newIndex = existingMaxIndex + 1

        guard let mediaSourceId = streamInfo.mediaSourceId else {
            logger.warning("No mediaSourceId — cannot build subtitle URL")
            return
        }

        let subtitleURL = provider.subtitleURL(
            itemId: item.id,
            mediaSourceId: mediaSourceId,
            subtitleIndex: newIndex
        )

        let track = SubtitleTrack(
            id: newIndex,
            title: displayName(for: language),
            language: language,
            isExternal: true,
            url: subtitleURL
        )

        videoManager.appendSubtitleTrack(track)
        videoManager.selectSubtitle(at: newIndex, externalURL: subtitleURL)
    }

    /// Record a language as recently used.
    private func recordLanguageUsage(_ language: String) {
        var recent = Defaults[.openSubtitlesRecentLanguages]
        // Remove if already present (will be moved to front)
        recent.removeAll { $0 == language }
        // Insert at front
        recent.insert(language, at: 0)
        // Cap at 5 most recent
        if recent.count > 5 {
            recent = Array(recent.prefix(5))
        }
        Defaults[.openSubtitlesRecentLanguages] = recent
    }

    /// Map OpenSubtitles errors to our UI error type.
    private func mapError(_ error: OpenSubtitlesError) -> SubtitleSearchError {
        switch error {
        case .rateLimited(let resetTime):
            .rateLimited(resetTime: resetTime, hasApiKey: hasApiKey)
        case .unauthorized:
            .unauthorized
        case .noResults:
            .noResults
        case .invalidResponse:
            .networkError(description: error.localizedDescription)
        case .networkError(let description):
            .networkError(description: description)
        case .downloadFailed:
            .downloadFailed
        }
    }

    /// Common ISO 639-1 → ISO 639-2/B mappings for Jellyfin.
    private static let languageCodeMap: [String: String] = [
        "aa": "aar", "ab": "abk", "af": "afr", "ak": "aka", "am": "amh",
        "an": "arg", "ar": "ara", "as": "asm", "av": "ava", "ay": "aym",
        "az": "aze", "ba": "bak", "be": "bel", "bg": "bul", "bh": "bih",
        "bi": "bis", "bm": "bam", "bn": "ben", "bo": "tib", "br": "bre",
        "bs": "bos", "ca": "cat", "ce": "che", "ch": "cha", "co": "cos",
        "cr": "cre", "cs": "cze", "cu": "chu", "cv": "chv", "cy": "wel",
        "da": "dan", "de": "ger", "dv": "div", "dz": "dzo", "ee": "ewe",
        "el": "gre", "en": "eng", "eo": "epo", "es": "spa", "et": "est",
        "eu": "baq", "fa": "per", "ff": "ful", "fi": "fin", "fj": "fij",
        "fo": "fao", "fr": "fre", "fy": "fry", "ga": "gle", "gd": "gla",
        "gl": "glg", "gn": "grn", "gu": "guj", "gv": "glv", "ha": "hau",
        "he": "heb", "hi": "hin", "ho": "hmo", "hr": "hrv", "ht": "hat",
        "hu": "hun", "hy": "arm", "hz": "her", "ia": "ina", "id": "ind",
        "ie": "ile", "ig": "ibo", "ii": "iii", "ik": "ipk", "io": "ido",
        "is": "ice", "it": "ita", "iu": "iku", "ja": "jpn", "jv": "jav",
        "ka": "geo", "kg": "kon", "ki": "kik", "kj": "kua", "kk": "kaz",
        "kl": "kal", "km": "khm", "kn": "kan", "ko": "kor", "kr": "kau",
        "ks": "kas", "ku": "kur", "kv": "kom", "kw": "cor", "ky": "kir",
        "la": "lat", "lb": "ltz", "lg": "lug", "li": "lim", "ln": "lin",
        "lo": "lao", "lt": "lit", "lu": "lub", "lv": "lav", "mg": "mlg",
        "mh": "mah", "mi": "mao", "mk": "mac", "ml": "mal", "mn": "mon",
        "mr": "mar", "ms": "may", "mt": "mlt", "my": "bur", "na": "nau",
        "nb": "nob", "nd": "nde", "ne": "nep", "ng": "ndo", "nl": "dut",
        "nn": "nno", "no": "nor", "nr": "nbl", "nv": "nav", "ny": "nya",
        "oc": "oci", "oj": "oji", "om": "orm", "or": "ori", "os": "oss",
        "pa": "pan", "pi": "pli", "pl": "pol", "ps": "pus", "pt": "por",
        "qu": "que", "rm": "roh", "rn": "run", "ro": "rum", "ru": "rus",
        "rw": "kin", "sa": "san", "sc": "srd", "sd": "snd", "se": "sme",
        "sg": "sag", "si": "sin", "sk": "slo", "sl": "slv", "sm": "smo",
        "sn": "sna", "so": "som", "sq": "alb", "sr": "srp", "ss": "ssw",
        "st": "sot", "su": "sun", "sv": "swe", "sw": "swa", "ta": "tam",
        "te": "tel", "tg": "tgk", "th": "tha", "ti": "tir", "tk": "tuk",
        "tl": "tgl", "tn": "tsn", "to": "ton", "tr": "tur", "ts": "tso",
        "tt": "tat", "tw": "twi", "ty": "tah", "ug": "uig", "uk": "ukr",
        "ur": "urd", "uz": "uzb", "ve": "ven", "vi": "vie", "vo": "vol",
        "wa": "wln", "wo": "wol", "xh": "xho", "yi": "yid", "yo": "yor",
        "za": "zha", "zh": "chi", "zu": "zul",
    ]
}

// MARK: - Error Type

/// Errors displayed in the subtitle search sheet UI.
enum SubtitleSearchError: Equatable {
    case noResults
    case apiKeyRequired
    case rateLimited(resetTime: String?, hasApiKey: Bool)
    case unauthorized
    case networkError(description: String)
    case downloadFailed

    var title: String {
        switch self {
        case .noResults: "No Subtitles Found"
        case .apiKeyRequired: "API Key Required"
        case .rateLimited: "Rate Limited"
        case .unauthorized: "Invalid API Key"
        case .networkError: "Connection Error"
        case .downloadFailed: "Download Failed"
        }
    }

    var message: String {
        switch self {
        case .noResults:
            "No subtitles were found for this item in the selected language. Try a different language."
        case .apiKeyRequired:
            "An OpenSubtitles API key is required to search for subtitles. You can get a free key at opensubtitles.com and add it in Settings → Subtitles."
        case .rateLimited(_, let hasApiKey):
            if hasApiKey {
                "Too many requests. Please try again later."
            } else {
                "You've reached the daily limit for subtitle downloads. Check your API key quota at opensubtitles.com."
            }
        case .unauthorized:
            "Your OpenSubtitles API key is invalid or expired. Please check it in Settings → Subtitles."
        case .networkError(let description):
            "Could not connect to OpenSubtitles: \(description)"
        case .downloadFailed:
            "Failed to download the subtitle file. Please try again."
        }
    }

    var systemImage: String {
        switch self {
        case .noResults: "text.badge.xmark"
        case .apiKeyRequired: "key.fill"
        case .rateLimited: "clock.badge.exclamationmark"
        case .unauthorized: "key.slash"
        case .networkError: "wifi.exclamationmark"
        case .downloadFailed: "arrow.down.circle.dotted"
        }
    }
}
