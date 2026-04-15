import Foundation

/// Maps common music genre name substrings to SF Symbols using fuzzy matching.
///
/// This is the music-specific counterpart to `GenreIconMap` (which targets
/// film/TV genres). The fallback icon is `"music.note"` instead of `"film"`.
enum MusicGenreIconMap {
    static func icon(for genre: String) -> String {
        let lower = genre.lowercased()
        for (keyword, symbol) in orderedMapping {
            if lower.localizedStandardContains(keyword) { return symbol }
        }
        return "music.note"
    }

    /// Ordered so more-specific matches (e.g. "hip-hop") come before general ones.
    private static let orderedMapping: [(String, String)] = [
        // Electronic / Dance
        ("electronic", "waveform"),
        ("electro", "waveform"),
        ("edm", "waveform"),
        ("techno", "waveform"),
        ("house", "waveform"),
        ("trance", "waveform"),
        ("drum and bass", "waveform"),
        ("dubstep", "waveform"),
        ("ambient", "moon.stars.fill"),
        ("synthwave", "waveform"),

        // Hip-Hop / Rap
        ("hip-hop", "mic.fill"),
        ("hip hop", "mic.fill"),
        ("rap", "mic.fill"),
        ("trap", "mic.fill"),

        // Rock variants
        ("punk", "bolt.fill"),
        ("metal", "flame.fill"),
        ("hard rock", "flame.fill"),
        ("grunge", "bolt.fill"),
        ("alternative", "sparkles"),
        ("indie", "sparkles"),
        ("rock", "guitars.fill"),

        // Jazz / Blues / Soul
        ("jazz", "pianokeys"),
        ("blues", "pianokeys"),
        ("soul", "heart.fill"),
        ("r&b", "heart.fill"),
        ("rnb", "heart.fill"),
        ("funk", "speaker.wave.2.fill"),
        ("gospel", "music.mic"),
        ("motown", "music.mic"),

        // Classical / Orchestral
        ("classical", "wand.and.stars"),
        ("orchestral", "wand.and.stars"),
        ("opera", "wand.and.stars"),
        ("symphony", "wand.and.stars"),
        ("chamber", "wand.and.stars"),
        ("baroque", "wand.and.stars"),

        // Country / Folk / Acoustic
        ("country", "guitars.fill"),
        ("folk", "leaf.fill"),
        ("acoustic", "guitars.fill"),
        ("bluegrass", "guitars.fill"),
        ("americana", "guitars.fill"),

        // Latin / World
        ("latin", "music.note.list"),
        ("reggaeton", "music.note.list"),
        ("salsa", "music.note.list"),
        ("bossa nova", "music.note.list"),
        ("world", "globe"),
        ("afrobeat", "globe"),
        ("african", "globe"),
        ("celtic", "leaf.fill"),
        ("reggae", "sun.max.fill"),
        ("ska", "sun.max.fill"),

        // Pop / Mainstream
        ("pop", "star.fill"),
        ("dance", "figure.dance"),
        ("disco", "figure.dance"),

        // Vocal / Spoken
        ("vocal", "music.mic"),
        ("choir", "music.mic"),
        ("a cappella", "music.mic"),
        ("spoken", "text.bubble.fill"),
        ("podcast", "text.bubble.fill"),

        // Other
        ("soundtrack", "film"),
        ("score", "film"),
        ("musical", "theatermasks.fill"),
        ("holiday", "snowflake"),
        ("christmas", "snowflake"),
        ("children", "figure.and.child.holdinghands"),
        ("kids", "figure.and.child.holdinghands"),
        ("new age", "moon.stars.fill"),
        ("lo-fi", "headphones"),
        ("lofi", "headphones"),
        ("chillout", "cup.and.saucer.fill"),
        ("chill", "cup.and.saucer.fill"),
        ("experimental", "waveform.path.ecg"),
        ("noise", "waveform.path.ecg"),
    ]
}
