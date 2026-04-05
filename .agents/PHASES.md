# Cove — Implementation Phases

## Phase 1: Foundation (SPM Package + Models)

**Goal:** Establish the project skeleton with all module targets and core domain types.

### Tasks

1. **Create `Packages/CoveKit/` SPM package** with `Package.swift` declaring all module targets:
   - `Models` — server-agnostic domain types (zero dependencies)
   - `MediaServerKit` — protocol contracts (depends on Models)
   - `JellyfinAPI` — Jellyfin DTOs, API client (depends on Models, Networking)
   - `JellyfinProvider` — protocol implementation (depends on JellyfinAPI, MediaServerKit)
   - `PlaybackEngine` — AVPlayer wrappers (depends on Models)
   - `DownloadManager` — background downloads (depends on Models, Persistence, Networking)
   - `Persistence` — GRDB database (depends on Models)
   - `Networking` — URLSession wrapper (depends on Models)
   - `ImageService` — Nuke configuration (depends on Models)

2. **Define `Models` module** with core domain types:
   - `ItemID`, `ServerType`, `MediaType` — foundational ID and enum types
   - `ServerConnection` — server URL, user ID, server type
   - `MediaItem`, `UserData` — generic media item with user state
   - `Artist`, `Album`, `Track`, `Playlist` — music types
   - `Movie`, `Series`, `Season`, `Episode` — video types
   - `MediaLibrary` — library metadata
   - `StreamInfo`, `MediaStream` — playback/streaming types
   - `AppError` — unified error enum
   - `ImageType`, `SortOptions`, `FilterOptions` — supporting types

3. **Wire the app target** to depend on `CoveKit` package.

4. **Create stub files** for all other modules so the full dependency graph compiles.

### Milestone

Project compiles with the full module structure. All imports resolve. `Models` types are usable from the app target.

---

## Phase 2: Networking + Jellyfin Auth

**Goal:** Connect to a Jellyfin server, authenticate, and persist the connection.

### Tasks

5. **`Networking` module** — `HTTPClient` wrapper around `URLSession` with `async/await`, request building, JSON decoding, auth header injection, error mapping.

6. **`JellyfinAPI` module** — DTOs for:
   - `GET /System/Info/Public` — server discovery (`PublicSystemInfo`)
   - `POST /Users/AuthenticateByName` — login (`AuthenticateByName` / `AuthenticationResult`)
   - Jellyfin auth header construction (`X-Emby-Authorization`)

7. **`Persistence` module** — GRDB setup:
   - `DatabaseManager` — create/open database, run migrations
   - `001_initial.sql` — `servers` table
   - `ServerRepository` — CRUD for server connections

8. **`MediaServerKit` module** — define `MediaServerProvider` protocol (connect/disconnect/libraries surface only).

9. **`JellyfinProvider` module** — implement `MediaServerProvider.connect()` using `JellyfinAPIClient`. Map DTOs to domain models.

10. **Keychain integration** — store/retrieve access tokens securely.

### Milestone

Can call `JellyfinProvider.connect(url:credentials:)` from a test and get back a valid auth token. Server connection persisted in database, token in Keychain.

---

## Phase 3: Login UI + Library Browsing

**Goal:** First visible UI — connect to a server, browse libraries with artwork.

### Tasks

11. **Auth UI** — Server URL entry → username/password login → store connection.

12. **Library browsing API** — Add to `JellyfinAPIClient`:
    - `GET /Library/VirtualFolders` — list libraries
    - `GET /Users/{id}/Items` — browse/filter items
    - `GET /Items/{itemId}` — single item detail
    - Item DTO → domain model mapping

13. **App shell** — Adaptive navigation:
    - `TabView` on iPhone (compact)
    - `NavigationSplitView` with sidebar on iPad/Mac (regular)
    - Dynamic tabs based on server libraries

14. **Image loading** — Integrate Nuke:
    - Configure `ImageService` module with disk + memory cache
    - Build Jellyfin image URLs (`/Items/{id}/Images/{type}`)
    - `LazyImage` in library grid views

15. **Library views** — Grid of posters/album art per library type.

### Milestone

Launch app → enter server URL → log in → see music/movie/TV libraries with artwork. First "it works" moment.

---

## Phase 4: Music Playback

**Goal:** Full music player with gapless playback, queue, and lock screen controls.

### Tasks

16. **`PlaybackEngine` module — `AudioPlaybackManager`:**
    - `AVQueuePlayer` lifecycle
    - Play queue model (ordered tracks, current index)
    - Queue operations: play next, play later, shuffle, repeat, reorder
    - Gapless playback via pre-inserting next 1-2 tracks
    - `AVAudioSession` category `.playback` for background audio
    - `MPNowPlayingInfoCenter` — lock screen metadata + artwork
    - `MPRemoteCommandCenter` — play, pause, next, previous, seek
    - Persist queue state to GRDB

17. **Music API endpoints** — Add to `JellyfinAPIClient`:
    - `GET /Artists` / `GET /Artists/AlbumArtists`
    - `GET /Users/{id}/Items` filtered by music types
    - `GET /Audio/{id}/universal` — audio stream URL
    - Playback reporting: `POST /Sessions/Playing`, `/Progress`, `/Stopped`

18. **Music UI:**
    - Album detail view (track list with play button)
    - Artist detail view (discography)
    - Music library views (artists, albums, playlists, genres)

19. **Now Playing bar** — persistent mini-player:
    - Floats above tab bar (iPhone) / bottom of content (iPad/Mac)
    - Album art, title, artist, play/pause, progress
    - Tap to expand to full-screen audio player
    - Persists across all navigation

20. **Full-screen audio player:**
    - Large album art
    - Playback controls (prev, play/pause, next, seek bar)
    - Queue view (up next, reorder, remove)
    - Shuffle and repeat toggles

### Milestone

Browse music library → tap album → tap track → music plays with gapless transitions, lock screen controls, and Now Playing bar across all tabs.

---

## Phase 5: Video Playback

**Goal:** Movies and TV shows with native player, subtitles, PiP, and continue watching.

### Tasks

21. **`PlaybackEngine` module — `VideoPlaybackManager`:**
    - `AVPlayer` for single video item
    - `StreamResolver` — inspect media info, decide direct play vs. transcode
    - `DeviceProfile` construction (AVPlayer capabilities, device-aware)
    - `AVPictureInPictureController` for PiP
    - Continue audio on screen lock

22. **Video API endpoints:**
    - `GET /Items/{id}/PlaybackInfo` — media sources, stream info
    - `GET /Videos/{id}/master.m3u8` — HLS transcode stream
    - `GET /Videos/{id}/stream` — direct stream
    - `GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.vtt` — subtitle tracks
    - `GET /Shows/{seriesId}/Episodes` — episodes list
    - `GET /Shows/{seriesId}/Seasons` — seasons list
    - `GET /Shows/NextUp` — next episode to watch

23. **Video player UI:**
    - Full-screen custom controls (play/pause, seek bar, time labels)
    - Subtitle picker (language selection)
    - PiP button
    - Auto-play next episode with 10-second countdown

24. **Movie/TV detail views:**
    - Movie detail: poster, backdrop, metadata, cast, play button
    - Series detail: season picker → episode list
    - Episode row: thumbnail, title, description, progress indicator

25. **Continue watching:**
    - Playback position reporting (start, progress every ~10s, stop)
    - `GET /UserItems/Resume` — resume items on home screen
    - Resume position indicator on movie/episode cards

### Milestone

Browse movies/TV → play a video → PiP works → resume where you left off → next episode auto-plays.

---

## Phase 6: Downloads & Offline

**Goal:** Download music, movies, and episodes for offline playback.

### Tasks

26. **`DownloadManager` module:**
    - `URLSessionConfiguration.background` for downloads that survive app suspension
    - Download state machine: `queued → downloading → paused → completed → failed`
    - State persisted in GRDB across app restarts
    - Resumable via HTTP range requests
    - Concurrency limit (max 3 simultaneous)
    - Batch operations (download album, season, playlist)

27. **Download storage:**
    - Files in `Library/Application Support/Downloads/{serverID}/{libraryType}/{itemID}/`
    - `isExcludedFromBackup = true` on all download files
    - Metadata JSON + images saved alongside media files

28. **Download UI:**
    - Download buttons on albums, movies, episodes, playlists
    - Download progress indicators (per-item and in downloads tab)
    - Downloads tab: grouped by type, storage usage summary
    - Swipe-to-delete individual downloads
    - Storage management screen (total space, per-library breakdown)

29. **Offline library:**
    - Persist full `MediaItem` models to database with `isDownloaded = true`
    - Offline-aware library queries (filter to downloaded items when no network)
    - Download and cache primary image + backdrop per item

30. **Offline playback:**
    - Detect network state (NWPathMonitor)
    - Play from local file path instead of server URL
    - Queue playback position reports for server sync when connectivity returns
    - Conflict resolution: latest timestamp wins

### Milestone

Download an album and a movie → go airplane mode → everything still plays with full artwork and metadata. Positions sync when back online.

---

## Status Key

| Symbol | Meaning |
|--------|---------|
| [ ] | Not started |
| [~] | In progress |
| [x] | Complete |

## Current Status

- [x] **Phase 1** — Foundation (SPM Package + Models)
- [x] **Phase 2** — Networking + Jellyfin Auth
- [x] **Phase 3** — Login UI + Library Browsing
- [x] **Phase 4** — Music Playback
- [ ] **Phase 5** — Video Playback
- [ ] **Phase 6** — Downloads & Offline