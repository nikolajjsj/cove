# Cove — Architecture & Design Plan

## Overview

Cove is a native Swift media client for Jellyfin servers, targeting iOS, iPadOS, and macOS. It provides a premium music player and video experience with first-class offline support. The architecture is server-agnostic — designed so additional media server backends (Plex, Navidrome, SMB, etc.) can be added in the future without touching the UI or playback layers.

**Working name:** Cove (placeholder)
**Bundle ID:** `com.nikolajjsj.jellyfin` (development)

---

## Platforms & Targets

| Platform | Status | Notes |
|----------|--------|-------|
| iOS | v1 | Primary target |
| iPadOS | v1 | Adaptive sidebar layout |
| macOS | v1 | Catalyst-free, native SwiftUI |
| tvOS | Architecture-ready, UI deferred | Shared core modules, platform-specific UI later |
| visionOS | Deferred | Dropped for now, easy to add later |

**Minimum deployment target:** iOS 26.4 / macOS 26.4 (latest only)

---

## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | **Swift 6** | Strict concurrency, `@MainActor` default isolation |
| UI | **SwiftUI** | Native, declarative, multi-platform |
| Architecture | **MVVM + @Observable** | Modern, testable, minimal boilerplate |
| Concurrency | **Structured concurrency (async/await, actors)** | Swift 6 strict mode, no Combine dependency |
| Networking | **URLSession + async/await** | Native, background download support |
| Database | **GRDB** | Type-safe SQLite, powerful queries, migrations, WAL mode |
| Image Loading | **Nuke** | Lightweight, SwiftUI-native (`LazyImage`), disk + memory cache |
| Video Playback | **AVPlayer** | Hardware decoding, PiP, AirPlay, system integration |
| Audio Playback | **AVQueuePlayer** | Gapless playback, background audio, lock screen controls |
| Auth Storage | **Keychain** | Secure token/credential storage |
| Logging | **os.Logger** | Zero-cost unified logging, per-module categories |
| Project Structure | **SPM multi-module** | Clean boundaries, fast builds, testable in isolation |

### Dependencies

- `GRDB` — SQLite database layer
- `Nuke` — image loading and caching
- `KeychainAccess` (or thin custom wrapper) — Keychain API convenience

No other third-party dependencies. No VLCKit, no Combine, no TCA.

---

## Project Structure

```
jellyfin/                                 # Xcode project root
  jellyfin/                               # App target (thin shell)
    jellyfinApp.swift                     # Entry point
    UI/
      App/                                # Root app structure, tab/sidebar coordination
      Auth/                               # Login, server connection UI
      Music/                              # Music library, album, artist, playlist views
      Video/                              # Movies, TV shows, episode views
      Player/
        NowPlayingBar.swift               # Persistent mini-player overlay
        AudioPlayerView.swift             # Full-screen music player
        VideoPlayerView.swift             # Full-screen video player
      Downloads/                          # Download management UI
      Search/                             # Global search
      Settings/                           # Preferences, storage management, server management
      Components/                         # Shared UI components (poster cards, list rows, etc.)
    Resources/
      Assets.xcassets

  Packages/
    CoveKit/                              # Local Swift Package (all shared logic)
      Package.swift
      Sources/
        Models/                           # Server-agnostic domain models (zero dependencies)
        MediaServerKit/                   # Protocol contracts for media server providers
        JellyfinAPI/                      # Jellyfin-specific: DTOs, API client, DeviceProfile
        JellyfinProvider/                 # Jellyfin implementation of MediaServerKit protocols
        PlaybackEngine/                   # AVPlayer wrappers, audio/video playback managers
        DownloadManager/                  # Background downloads, queue, resume, state machine
        Persistence/                      # GRDB database, migrations, repositories
        Networking/                       # Shared URLSession config, auth interceptor, reachability
        ImageService/                     # Nuke configuration, offline image cache
      Tests/
        ModelsTests/
        JellyfinAPITests/
        JellyfinProviderTests/
        PlaybackEngineTests/
        PersistenceTests/
        DownloadManagerTests/
```

---

## Module Dependency Graph

Dependencies flow strictly downward. No circular dependencies.

```
App Target (UI)
  |
  +-- Models              (zero dependencies — pure Swift types)
  +-- MediaServerKit       (depends on: Models)
  +-- JellyfinAPI          (depends on: Models, Networking)
  +-- JellyfinProvider     (depends on: JellyfinAPI, MediaServerKit)
  +-- PlaybackEngine       (depends on: Models)
  +-- DownloadManager      (depends on: Models, Persistence, Networking)
  +-- Persistence          (depends on: Models, GRDB)
  +-- Networking           (depends on: Models)
  +-- ImageService         (depends on: Models, Nuke)
```

Key constraints:
- `Models` has **zero** dependencies — it is pure Swift value types and enums
- `MediaServerKit` depends **only** on `Models` — it defines the protocol contract
- `PlaybackEngine` does **not** know about servers — it receives URLs and metadata
- `JellyfinProvider` is the **only** module that knows about Jellyfin specifics
- The app target wires everything together via dependency injection

---

## Server-Agnostic Abstraction Layer

### Capability-Based Protocol Design

The base protocol defines what every media server must support:

```swift
protocol MediaServerProvider {
    // Connection
    func connect(url: URL, credentials: Credentials) async throws -> ServerConnection
    func disconnect() async

    // Library browsing
    func libraries() async throws -> [MediaLibrary]
    func items(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions) async throws -> [MediaItem]
    func item(id: ItemID) async throws -> MediaItem

    // Images
    func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL?

    // Search
    func search(query: String, mediaTypes: [MediaType]) async throws -> SearchResults
}
```

Optional capability protocols that servers adopt if they support the feature:

```swift
protocol MusicProvider: MediaServerProvider {
    func albums(artist: ArtistID) async throws -> [Album]
    func tracks(album: AlbumID) async throws -> [Track]
    func playlists() async throws -> [Playlist]
    func lyrics(track: TrackID) async throws -> Lyrics?
    // ...
}

protocol VideoProvider: MediaServerProvider {
    func seasons(series: SeriesID) async throws -> [Season]
    func episodes(season: SeasonID) async throws -> [Episode]
    func resumeItems() async throws -> [MediaItem]
    func streamURL(for item: MediaItem, profile: DeviceProfile?) async throws -> StreamInfo
    // ...
}

protocol TranscodingProvider: MediaServerProvider {
    func deviceProfile() -> DeviceProfile
    func transcodedStreamURL(for item: MediaItem, profile: DeviceProfile) async throws -> URL
}

protocol PlaybackReportingProvider: MediaServerProvider {
    func reportPlaybackStart(item: MediaItem, position: TimeInterval) async throws
    func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws
    func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws
}

protocol DownloadableProvider: MediaServerProvider {
    func downloadURL(for item: MediaItem, profile: DeviceProfile?) async throws -> URL
}
```

The UI checks capabilities at runtime:

```swift
if let musicProvider = activeServer as? MusicProvider {
    // Show music library tab
}
if let videoProvider = activeServer as? VideoProvider {
    // Show movies/TV tabs
}
```

### Server-Specific Isolation

Each server backend lives in its own module:

- `JellyfinProvider/` — implements `MediaServerProvider`, `MusicProvider`, `VideoProvider`, `TranscodingProvider`, `PlaybackReportingProvider`, `DownloadableProvider`
- (future) `PlexProvider/` — implements applicable protocols
- (future) `NavidromeProvider/` — implements `MediaServerProvider`, `MusicProvider` only
- (future) `SMBProvider/` — implements `MediaServerProvider` with basic file browsing

Each provider contains:
- **DTOs** — server-specific response types (Codable)
- **API client** — server-specific HTTP client
- **Mapper** — converts DTOs to shared `Models` types
- **Protocol implementation** — ties it all together

---

## Domain Models (Server-Agnostic)

All models are plain Swift types in the `Models` module. No server-specific fields.

### Core Types

```swift
struct MediaItem: Identifiable, Hashable, Codable {
    let id: ItemID
    let title: String
    let overview: String?
    let mediaType: MediaType
    let dateAdded: Date?
    let userData: UserData?
    // ...
}

enum MediaType: String, Codable {
    case movie
    case series
    case season
    case episode
    case album
    case artist
    case track
    case playlist
    case book          // Future
    case podcast       // Future
}

struct UserData: Codable {
    var isFavorite: Bool
    var playbackPosition: TimeInterval
    var playCount: Int
    var isPlayed: Bool
    var lastPlayedDate: Date?
}
```

### Music-Specific

```swift
struct Artist: Identifiable, Codable { ... }
struct Album: Identifiable, Codable { ... }
struct Track: Identifiable, Codable { ... }
struct Playlist: Identifiable, Codable { ... }
struct Lyrics: Codable { ... }            // Future
```

### Video-Specific

```swift
struct Movie: Identifiable, Codable { ... }
struct Series: Identifiable, Codable { ... }
struct Season: Identifiable, Codable { ... }
struct Episode: Identifiable, Codable { ... }
```

### Playback & Streaming

```swift
struct StreamInfo {
    let url: URL
    let isTranscoded: Bool
    let mediaStreams: [MediaStream]       // Audio tracks, subtitle tracks
    let directPlaySupported: Bool
}

struct MediaStream {
    let index: Int
    let type: MediaStreamType             // .audio, .subtitle, .video
    let codec: String
    let language: String?
    let title: String?
    let isExternal: Bool
}

struct DeviceProfile { ... }              // Lives in provider, but shared shape
```

### Server & Auth

```swift
struct ServerConnection: Identifiable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let userId: String
    let serverType: ServerType            // .jellyfin, .plex, .navidrome, .smb (future)
}

enum ServerType: String, Codable {
    case jellyfin
    // Future: .plex, .navidrome, .smb
}
```

---

## Jellyfin API Client

Hand-rolled, lean API client. Only the endpoints we actually use.

### Key Endpoints

| Area | Endpoint | Purpose |
|---|---|---|
| Auth | `POST /Users/AuthenticateByName` | Login |
| Libraries | `GET /Library/VirtualFolders` | List libraries |
| Items | `GET /Users/{id}/Items` | Browse/filter items |
| Item detail | `GET /Users/{id}/Items/{itemId}` | Single item with full metadata |
| Images | `GET /Items/{id}/Images/{type}` | Poster, backdrop, primary |
| Audio stream | `GET /Audio/{id}/universal` | Audio streaming URL |
| Video stream | `GET /Videos/{id}/master.m3u8` | HLS video stream |
| Direct stream | `GET /Items/{id}/Download` | Direct file download |
| Subtitles | `GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.vtt` | External subtitle track |
| Playback start | `POST /Sessions/Playing` | Report playback started |
| Playback progress | `POST /Sessions/Playing/Progress` | Report position (~10s interval) |
| Playback stop | `POST /Sessions/Playing/Stopped` | Report playback stopped |
| Resume items | `GET /Users/{id}/Items/Resume` | Continue watching |
| Search | `GET /Items` with `searchTerm` | Global search |
| Favorites | `POST /Users/{id}/FavoriteItems/{itemId}` | Toggle favorite |
| Played | `POST /Users/{id}/PlayedItems/{itemId}` | Mark as played |

### Stream Resolution (Hybrid Approach)

```
StreamResolver:
  1. Fetch item's MediaSources (codec, container, subtitle info)
  2. Check against DeviceProfile capabilities
  3. If direct-playable → return direct stream URL
  4. If needs remux only (e.g. MKV → HLS, same codecs) → request remux URL
  5. If needs transcode → request HLS transcode URL
  6. Attach external subtitle tracks (SRT/VTT) as side-loaded URLs
  7. Flag ASS/SSA/PGS subtitles for server-side burn-in
```

### DeviceProfile (AVPlayer Capabilities)

The `JellyfinProvider` builds a `DeviceProfile` reporting what the client can direct-play:

**Direct Play (no server work):**
- Video: H.264, H.265/HEVC in MP4/MOV containers
- Audio: AAC, ALAC, MP3, FLAC, Opus in MP4/M4A/MP3/FLAC containers
- Subtitles: SRT, VTT (external tracks)

**Requires Remux (container change, no re-encoding):**
- H.264/H.265 in MKV container → remux to HLS (fast, low server CPU)

**Requires Transcode (re-encoding):**
- Video codecs: VP9, AV1 (on older devices without hardware decode)
- Audio codecs: AC3, DTS, TrueHD → transcode to AAC
- Subtitles: ASS/SSA, PGS → burn into video stream

The profile is **device-aware** — queries the hardware at runtime to determine codec support (e.g., AV1 hardware decode on A17+ chips).

---

## Playback Engine

### Audio Playback (`AudioPlaybackManager`)

An `@Observable` singleton managing all music playback.

**Responsibilities:**
- `AVQueuePlayer` lifecycle and item management
- Play queue (ordered list of tracks, current index)
- Queue operations: play next, play later, shuffle, repeat, reorder, remove
- Gapless playback via pre-inserting next 1-2 tracks into `AVQueuePlayer`
- Background audio via `AVAudioSession` category `.playback`
- `MPNowPlayingInfoCenter` — lock screen metadata, artwork
- `MPRemoteCommandCenter` — play, pause, next, previous, seek, rating
- Persist queue state to local database (survives app termination)
- Playback position reporting to server (online) or queued for sync (offline)

**Queue model (mirrors Apple Music):**
- Playing a song from an album/playlist auto-fills queue with remaining tracks
- "Play Next" inserts at top of Up Next
- "Play Later" appends to end
- Shuffle mode randomizes upcoming queue, preserves history
- Repeat modes: off, repeat all, repeat one
- Queue persisted to GRDB on every change

### Video Playback (`VideoPlaybackManager`)

An `@Observable` class (not singleton — tied to a player view's lifecycle).

**Responsibilities:**
- `AVPlayer` lifecycle for a single video item
- Stream resolution (direct play vs. transcode) via provider
- Subtitle track selection (external SRT/VTT loaded client-side)
- PiP support via `AVPictureInPictureController`
- AirPlay (enabled by default on `AVPlayer`)
- Continue audio on screen lock (video rendering pauses, audio continues)
- Playback position reporting to server
- Auto-play next episode with 10-second countdown
- Pre-resolve next episode stream URL for fast transition

### Shared Concerns

Both managers handle:
- AirPlay (free with AVPlayer, `allowsExternalPlayback = true`)
- Audio session management (`.playback` category)
- Remote command center integration
- Playback position persistence (local DB + server reporting)

### CarPlay (Architecture-Ready, UI Deferred)

The `AudioPlaybackManager` is fully decoupled from UI. CarPlay and the main app drive the same manager instance. `MPRemoteCommandCenter` setup from day one means CarPlay gets basic controls for free. The CarPlay browse UI (`CPTemplateApplicationScene`) will be a separate entry point added later.

---

## Offline & Downloads

### Download Strategy

| Media Type | Download Format | Rationale |
|---|---|---|
| Music (tracks) | Original file (FLAC, MP3, AAC, etc.) | All common audio codecs are AVPlayer-compatible |
| Video (movies/episodes) | Original if direct-playable; device-compatible transcode if not | Check against DeviceProfile; request server transcode for incompatible formats |
| Images | Primary + backdrop per item | Full offline visual experience |
| Metadata | Full item model | Offline library is fully browsable |

### Download Manager (`DownloadManager`)

An `@Observable` singleton coordinating all downloads.

**Implementation:**
- `URLSessionConfiguration.background` — downloads continue when app is suspended/terminated
- Download state machine per item: `queued → downloading → paused → completed → failed`
- State persisted in GRDB (survives app restarts)
- Resumable via HTTP range requests
- Concurrency limit: max 3 simultaneous downloads
- Priority queue: user-initiated downloads jump ahead of batch downloads
- Batch operations: download entire album, season, or playlist

### Storage

- **Location:** `Library/Application Support/Downloads/` — hidden from Files app, survives app updates
- **Organization:** `{serverID}/{libraryType}/{itemID}/` — media file + metadata JSON + images
- **Backup exclusion:** `isExcludedFromBackup = true` on all download files
- **Storage management UI:** total space used, per-library breakdown, delete individual items
- **No hard limit:** user manages their own storage; show warnings when device storage is low

### Offline Metadata & Images

When an item is downloaded:
1. Media file is saved to disk
2. Full `MediaItem` model is persisted to the database with `isDownloaded = true`
3. Primary image and backdrop are downloaded and cached alongside the media file
4. For albums: all track metadata + album art; for seasons: all episode metadata + show art

The offline library is a fully browsable, visually rich subset of the server library.

### Offline Playback Position Sync

When playing offline content:
- Playback positions are stored locally in the database
- When connectivity returns, queued position reports are synced to the server
- Conflict resolution: latest timestamp wins (local or server)

---

## Local Database (GRDB)

### Schema

**Server & Auth:**
- `servers` — id, name, url, server_type, user_id, created_at
- (Keychain: access tokens keyed by server ID)

**Library Cache:**
- `media_items` — id, server_id, title, overview, media_type, json_metadata, date_added, updated_at
- `user_data` — item_id, server_id, is_favorite, playback_position, play_count, is_played, last_played_at
- `images` — item_id, image_type, url, local_path (if cached), updated_at

**Music-Specific:**
- `artists` — id, server_id, name, overview, sort_name
- `albums` — id, server_id, artist_id, title, year, genre, track_count
- `tracks` — id, server_id, album_id, artist_id, title, track_number, disc_number, duration, codec

**Video-Specific:**
- `movies` — id, server_id, title, year, runtime, genre, community_rating
- `series` — id, server_id, title, year, status, genre
- `seasons` — id, server_id, series_id, season_number, title
- `episodes` — id, server_id, season_id, series_id, episode_number, title, runtime

**Downloads:**
- `downloads` — id, item_id, server_id, state (queued/downloading/paused/completed/failed), progress, file_path, file_size, created_at, updated_at
- `pending_sync` — id, item_id, server_id, action (playback_report/favorite_toggle/played_toggle), payload_json, created_at

**Playback:**
- `playback_queue` — id, track_id, position_in_queue, inserted_at (persisted audio queue)
- `playback_state` — singleton row: current_track_id, position, shuffle, repeat_mode, volume

**Preferences:**
- `preferences` — key-value store for app settings (theme, preferred subtitle language, sort orders, etc.)

### Migrations

- Numbered SQL files: `001_initial.sql`, `002_add_downloads.sql`, etc.
- Run automatically on app launch via GRDB's `DatabaseMigrator`
- Forward-only (no down migrations)
- Each migration is idempotent and tested

---

## Navigation & UI

### Adaptive Layout

| Platform | Pattern | Implementation |
|---|---|---|
| iPhone (compact) | `TabView` | Tabs: Home, Music, Video, Downloads, Search, Settings |
| iPad (regular) | `NavigationSplitView` + sidebar | Sidebar with same sections as tabs |
| Mac (regular) | `NavigationSplitView` + sidebar | Native Mac sidebar, same as iPad |

Tab/sidebar items are **dynamic** — driven by the libraries available on the connected server. If the server has no music library, the Music tab doesn't appear.

### Now Playing Bar

A persistent mini-player bar floating above the tab bar (iPhone) or at the bottom of the content area (iPad/Mac). Shows:
- Album art thumbnail
- Track title + artist
- Play/pause button
- Progress indicator

Tapping expands to the full-screen audio player. This is the single hardest UI component to get right — it must overlay all navigation, persist across tab/sidebar changes, and animate smoothly between mini and full states.

### Navigation Model

- SwiftUI `NavigationStack(path:)` with typed navigation destinations
- Destination-driven routing (enables deep linking later)
- Each tab/sidebar section owns its own `NavigationStack`
- Video player is presented as a full-screen cover
- Audio player expands from the Now Playing bar as a sheet/cover

### Key Screens

**Home:**
- Continue Watching (resume items from server)
- Recently Added (latest movies, episodes, albums)
- Favorites

**Music:**
- Artists, Albums, Playlists, Genres, Songs
- Album detail → track list
- Artist detail → discography
- Now Playing (full-screen player with queue)

**Video:**
- Movies library (grid of posters)
- TV Shows library (grid of posters)
- Movie detail → play button, metadata, cast
- Series detail → season picker → episode list
- Video player (full-screen, custom controls)

**Downloads:**
- Downloaded items grouped by type (Music, Movies, TV)
- Storage usage summary
- Download queue / in-progress items

**Search:**
- Global search across all media types
- Scoped by media type (filter chips)

**Settings:**
- Server management (add/remove/switch servers)
- Playback preferences (subtitle language, audio quality)
- Download preferences (quality, Wi-Fi only toggle)
- Storage management (clear cache, manage downloads)
- About / debug info

---

## Authentication & Multi-Server

### Multi-Server Support (Day One)

- Users can add multiple server connections
- Each connection: server URL + server type + user ID + access token
- One "active" server at a time; user can switch via Settings or a server picker
- Server connections stored in the database; tokens in Keychain
- Future-proofed: adding a Plex server means adding a `PlexProvider` that implements the same protocols

### Auth Flow

1. User enters server URL
2. App discovers server info (Jellyfin: `GET /System/Info/Public`)
3. User enters username + password
4. Provider authenticates (Jellyfin: `POST /Users/AuthenticateByName`)
5. Access token stored in Keychain, server connection stored in database
6. App navigates to the main library view

### Token Refresh / Expiry

- Jellyfin tokens don't expire by default, but the server admin can revoke them
- On 401 response, the app prompts re-authentication
- An `ErrorHandler` service coordinates auth-expired flows globally

---

## Concurrency Model

**Swift 6 strict concurrency** with `@MainActor` as the default isolation.

| Component | Isolation | Rationale |
|---|---|---|
| SwiftUI Views | `@MainActor` (default) | UI must be on main thread |
| ViewModels (`@Observable`) | `@MainActor` (default) | Drive UI, publish state |
| `AudioPlaybackManager` | `@MainActor` | Drives UI state, AVPlayer must be accessed from a consistent thread |
| `VideoPlaybackManager` | `@MainActor` | Same as above |
| `JellyfinAPIClient` | `nonisolated` (async methods) | Network calls run on cooperative pool |
| `DownloadManager` | `@MainActor` for state, `nonisolated` for URLSession delegate | State drives UI; delegate callbacks come from system |
| GRDB database access | GRDB's internal serial queue | GRDB handles thread safety; callers `await` results |
| `StreamResolver` | `nonisolated` | Pure computation, no UI |

---

## Error Handling

### `AppError` Enum

Defined in `Models`, used across all modules:

```swift
enum AppError: Error, LocalizedError {
    case networkUnavailable
    case serverUnreachable(url: URL)
    case authExpired(serverName: String)
    case authFailed(reason: String)
    case playbackFailed(reason: String)
    case downloadFailed(itemTitle: String, reason: String)
    case storageFull
    case itemNotFound(id: ItemID)
    case serverError(statusCode: Int, message: String?)
    case unknown(underlying: Error)
}
```

Each module maps its internal errors to `AppError`. The UI presents errors contextually:
- Inline/banner for recoverable errors (no network, retry available)
- Alert/sheet for critical errors (auth expired → re-login)
- Toast for transient issues (download paused, will retry)

---

## Logging

Apple's unified logging via `os.Logger`, one logger per module:

```swift
// In JellyfinAPI module
let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "JellyfinAPI")

// In PlaybackEngine module
let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "PlaybackEngine")

// In DownloadManager module
let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "DownloadManager")
```

Categories: `JellyfinAPI`, `JellyfinProvider`, `PlaybackEngine`, `DownloadManager`, `Persistence`, `Networking`, `ImageService`, `UI`

Integrates with Console.app for on-device debugging. Zero performance cost when not being read.

---

## Testing Strategy

**Unit tests for core modules** — high-value, low-cost:

| Module | What's Tested |
|---|---|
| `Models` | Codable round-trips, equality, computed properties |
| `JellyfinAPI` | DTO decoding from JSON fixtures, URL construction |
| `JellyfinProvider` | DTO → domain model mapping, stream resolution logic |
| `PlaybackEngine` | Queue state machine (add, remove, shuffle, next, previous) |
| `Persistence` | Database migrations, CRUD operations, complex queries |
| `DownloadManager` | State machine transitions (queued → downloading → completed/failed) |

No UI tests or snapshot tests for v1 — the UI will change rapidly. Integration tests (hitting a real server) deferred until the API layer stabilizes.

---

## Future Considerations (Not v1)

These are explicitly deferred but the architecture accommodates them:

- **Books / Audiobooks** — new `MediaType` cases, new `BookProvider` protocol, new UI tab. The `Models` module's `MediaType` enum already has room. The adaptive navigation already supports dynamic tabs.
- **Podcasts** — similar to audiobooks. `MediaType.podcast`, provider protocol extension.
- **Plex / Navidrome / SMB backends** — new provider modules implementing `MediaServerKit` protocols. No changes to UI, playback, or downloads.
- **CarPlay UI** — `CPTemplateApplicationScene` entry point driving `AudioPlaybackManager`. Architecture ready.
- **tvOS UI** — new app target, shared `CoveKit` package, focus-engine-based SwiftUI views.
- **visionOS** — same as tvOS: new target, shared core.
- **Lyrics** — `Lyrics` model exists, `MusicProvider.lyrics()` method defined, UI deferred.
- **Scrobbling (Last.fm)** — observer on playback events, no core changes needed.
- **Widgets / Lock Screen** — `MPNowPlayingInfoCenter` handles lock screen. Home screen widgets are additive.
- **Deep Linking** — navigation is destination-driven (`NavigationStack(path:)`), so a `DeepLinkRouter` maps URLs to destinations. No current implementation.

---

## Decisions Log

| # | Decision | Choice |
|---|---|---|
| 1 | Relationship to Swiftfin | Independent new client, learn from their pain points |
| 2 | App name | "Cove" (placeholder) |
| 3 | tvOS | Architecture-ready, UI deferred |
| 4 | visionOS | Dropped for now |
| 5 | Min deployment target | iOS/macOS 26.4 (latest only) |
| 6 | Project structure | SPM multi-module |
| 7 | Architecture pattern | MVVM + @Observable |
| 8 | Jellyfin API client | Hand-rolled, lean |
| 9 | Server abstraction | Capability-based protocols |
| 10 | DTO isolation | Per-provider SPM modules |
| 11 | Video playback engine | AVPlayer + server-side transcoding fallback |
| 12 | Audio playback engine | AVQueuePlayer, dedicated AudioPlaybackManager |
| 13 | Background audio | Yes, for both music and video audio |
| 14 | Download format | Original audio; compatible transcode for video |
| 15 | Download storage | Library/Application Support/, excluded from backup |
| 16 | Download resumability | URLSession background tasks, HTTP range resume |
| 17 | Offline metadata | Full model + images persisted on download |
| 18 | Database | GRDB |
| 19 | Navigation | Adaptive (TabView iPhone, Sidebar iPad/Mac) |
| 20 | Music queue model | Apple Music-style (auto-fill, play next/later, persist) |
| 21 | Image loading | Nuke |
| 22 | Multi-server | Supported from day one |
| 23 | Credential storage | Keychain |
| 24 | Streaming approach | Hybrid (direct stream if compatible, HLS transcode fallback) |
| 25 | DeviceProfile | Comprehensive, device-aware AVPlayer capability reporting |
| 26 | Subtitles | SRT/VTT client-side; ASS/PGS server burn-in |
| 27 | Playback reporting | Start, progress (10s), stop; offline queued for sync |
| 28 | Gapless playback | AVQueuePlayer with 1-2 track lookahead |
| 29 | Lyrics | Model defined, UI deferred |
| 30 | Scrobbling | Deferred (server-side plugins sufficient) |
| 31 | CarPlay | Architecture-ready (MPRemoteCommandCenter day one), UI deferred |
| 32 | AirPlay | Free with AVPlayer, enabled by default |
| 33 | Continue watching / next episode | Auto-play next with 10s countdown; resume items on home |
| 34 | Picture-in-Picture | Day one, native AVPlayer PiP |
| 35 | Package layout | CoveKit local Swift package with 9 module targets |
| 36 | Dependency strictness | Strict (no circular deps, minimal coupling) |
| 37 | Testing | Unit tests on core modules |
| 38 | Logging | os.Logger per module |
| 39 | Concurrency | Swift 6 strict, @MainActor default |
| 40 | Error handling | AppError enum, contextual UI presentation |
| 41 | Deep linking | Architecture-ready (destination-driven nav), deferred |
| 42 | Widgets | Deferred (MPNowPlayingInfoCenter covers lock screen) |
| 43 | Working name | "Cove" |