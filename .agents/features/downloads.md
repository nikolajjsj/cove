# Downloads Redesign — Feature Plan

> **Status**: Approved design, ready for implementation
> **Scope**: Offline downloads for movies, TV shows, episodes, albums, tracks with full metadata, artwork, subtitles, and real-time progress

---

## Overview

Redesign the downloads feature so users can download movies, TV shows (with season picker), individual episodes, music albums, and individual songs for fully offline playback. All media item metadata, artwork, and subtitles are persisted locally so the downloads page can render the same UI components used in the online library.

---

## 1. Database Schema (Migration `003_offline_redesign`)

### New table: `offline_metadata`

| Column        | Type             | Notes                                      |
|---------------|------------------|--------------------------------------------|
| `itemId`      | TEXT NOT NULL     | Jellyfin item ID                           |
| `serverId`    | TEXT NOT NULL     | FK → servers, ON DELETE CASCADE             |
| `mediaType`   | TEXT NOT NULL     | Discriminator for deserialization           |
| `metadataJSON`| BLOB NOT NULL     | Forward-compatible JSON blob (all-optional) |
| `updatedAt`   | DATETIME NOT NULL | Last fetch timestamp                       |
|               |                  | **PRIMARY KEY (itemId, serverId)**          |

### New table: `download_groups`

| Column      | Type             | Notes                                          |
|-------------|------------------|-------------------------------------------------|
| `id`        | TEXT NOT NULL PK  | UUID string                                    |
| `itemId`    | TEXT NOT NULL     | Parent item's Jellyfin ID (series, album, etc) |
| `serverId`  | TEXT NOT NULL     | FK → servers, ON DELETE CASCADE                 |
| `mediaType` | TEXT NOT NULL     | series, album, season                          |
| `title`     | TEXT NOT NULL     | Display title                                  |
| `createdAt` | DATETIME NOT NULL |                                                |
|             |                  | **UNIQUE (itemId, serverId)**                  |

### Alter `downloads` table

| New Column | Type | Notes                                                   |
|------------|------|---------------------------------------------------------|
| `groupId`  | TEXT | FK → download_groups, nullable (movies have no group)   |

---

## 2. Models

### `OfflineMediaMetadata`

A `Codable` struct with **all optional fields** (except identifiers) for forward compatibility. Adding a new optional field never breaks existing database rows — missing JSON keys decode as `nil`.

**Core fields** (from `MediaItem`):
- `itemId`, `serverId`, `mediaType` (required identifiers)
- `title`, `overview`, `genres`, `productionYear`, `runTimeTicks`
- `communityRating`, `officialRating`, `criticRating`
- `userData` (favorite, play position, play count, played status)

**Episode-specific**: `seriesId`, `seasonId`, `episodeNumber`, `seasonNumber`, `seriesName`

**Series-specific**: `status`, `seasonCount`, `episodeCount`

**Album-specific**: `artistId`, `artistName`, `year`, `genre`, `trackCount`, `duration`

**Track-specific**: `albumId`, `albumName`, `artistId`, `artistName`, `trackNumber`, `discNumber`, `duration`, `codec`

**Offline asset paths** (relative paths to downloaded files):
- `primaryImagePath: String?`
- `backdropImagePath: String?`
- `subtitles: [OfflineSubtitle]?` — array of `(index, language, title, localPath)`

### `DownloadGroup`

Value type representing a logical group of downloads (a season, an album).
- `id`, `itemId`, `serverId`, `mediaType`, `title`, `createdAt`
- Derived `state`: computed from children (all completed → completed, any downloading → downloading, etc.)
- Derived `progress`: average of children's progress

### `DownloadItem` (extended)

- Adds `groupId: String?` — links to parent `DownloadGroup`

---

## 3. Persistence Layer

### `OfflineMetadataRepository`
- `save(_ metadata: OfflineMediaMetadata)`
- `fetch(itemId:serverId:) -> OfflineMediaMetadata?`
- `fetchAll(serverId:mediaType:) -> [OfflineMediaMetadata]`
- `delete(itemId:serverId:)`
- `deleteAll(serverId:)`

### `DownloadGroupRepository`
- `save(_ group: DownloadGroup)`
- `fetch(id:) -> DownloadGroup?`
- `fetch(itemId:serverId:) -> DownloadGroup?`
- `fetchAll(serverId:) -> [DownloadGroup]`
- `delete(id:)` — cascades to child DownloadItems
- `deleteAll(serverId:)`

### `DownloadRepository` — New observation APIs (GRDB `ValueObservation`)
- `observeAll(serverId:) -> AsyncStream<[DownloadItem]>` — DownloadsView main list
- `observeActive(serverId:) -> AsyncStream<[DownloadItem]>` — active/failed section
- `observeOne(itemId:serverId:) -> AsyncStream<DownloadItem?>` — DownloadButton on detail views
- `observeGroup(groupId:) -> AsyncStream<[DownloadItem]>` — album/season detail in downloads

---

## 4. Download Manager Changes

### Batch enqueue API

```swift
// Enqueue an entire season
func enqueueSeason(
    series: MediaItem, season: MediaItem, episodes: [MediaItem],
    serverId: String, provider: JellyfinServerProvider
) async throws -> DownloadGroup

// Enqueue an entire album
func enqueueAlbum(
    album: MediaItem, tracks: [MediaItem],
    serverId: String, provider: JellyfinServerProvider
) async throws -> DownloadGroup
```

### Batch enqueue flow (e.g., season)

1. Create a `DownloadGroup` for the season, save to DB
2. Fetch full `MediaItem` for series, season, and all episodes → save each to `offline_metadata`
3. Download primary artwork for series, season, and each episode → save paths in metadata
4. Download backdrop artwork for series → save path in metadata
5. For each episode, fetch `PlaybackInfo` to discover external subtitles
6. Enqueue episodes sorted by `episodeNumber` ascending
7. Each `DownloadItem` gets the `groupId` of the season group
8. Download external subtitles alongside each episode's media file

### WiFi-only enforcement

- Check `Defaults[.downloadOverCellular]` in `startNextDownloadsIfNeeded()`
- If false and `networkMonitor.isExpensive`, don't start new downloads
- Observe network changes — auto-resume when WiFi reconnects

### Group completion notification

- After each item completes, check if all siblings in the group are complete
- If group just completed, post a `UNNotificationRequest`:
  - *"Abbey Road is ready to listen."*
  - *"Breaking Bad Season 2 is ready to watch."*
  - *"Inception is ready to watch."* (single movies, no group)

---

## 5. Image Management

### File layout

```
Downloads/{serverId}/movie/{itemId}/media.mp4
Downloads/{serverId}/movie/{itemId}/primary.jpg
Downloads/{serverId}/movie/{itemId}/backdrop.jpg
Downloads/{serverId}/episode/{itemId}/media.mp4
Downloads/{serverId}/episode/{itemId}/primary.jpg
Downloads/{serverId}/episode/{itemId}/sub_0_en.vtt
Downloads/{serverId}/episode/{itemId}/sub_1_es.vtt
```

Parent artwork (series, album, artist) stored under their own item directory even though no media file exists:

```
Downloads/{serverId}/series/{seriesItemId}/primary.jpg
Downloads/{serverId}/series/{seriesItemId}/backdrop.jpg
Downloads/{serverId}/album/{albumItemId}/primary.jpg
```

### Image loading integration

- Do **not** rely on Nuke's disk cache (LRU eviction makes it unreliable for offline)
- Add `localImageURL(itemId:serverId:imageType:) -> URL?` on `DownloadStorage` or the metadata repo
- Image views check for local file first → load from `file://` URL → otherwise fall back to remote Nuke pipeline

---

## 6. Subtitle Downloads

- At enqueue time, fetch `PlaybackInfo` to discover available subtitle streams
- Download **external** subtitle files (`.srt`, `.vtt`, `.ass`) alongside the media file
- Internal/embedded subtitles (baked into the video container) don't need separate downloads
- Store subtitle file paths in `OfflineMediaMetadata.subtitles` so the player can find them

---

## 7. Settings — WiFi-Only Toggle

Using `sindresorhus/Defaults`:

```swift
import Defaults

extension Defaults.Keys {
    static let downloadOverCellular = Key<Bool>("downloadOverCellular", default: false)
}
```

New row in `SettingsView` under "Downloads & Storage": `Toggle("Download over Cellular", isOn: ...)`.

---

## 8. Playback Wiring

### Audio (`wireUpPlayer`)
- `streamURLResolver` checks `downloadManager.localFileURL(for:)` first
- Returns local `file://` URL if downloaded, remote URL otherwise
- If offline and track not downloaded, skip to next track

### Video
- Same pattern — resolve local file URL first, fallback to `provider.streamURL()`
- Load subtitles from local `.vtt` files when offline (paths stored in `OfflineMediaMetadata.subtitles`)

---

## 9. Downloads Page UI — Hybrid Layout

Single scrollable `NavigationStack` page with auto-hiding sections:

### Section 1: Downloads (top, auto-hides when empty)
Compact list rows. Active items first (downloading → queued → paused), then failed items below a subtle divider. Each active item shows a progress ring/bar. Failed items show error message + retry button.

### Section 2: Movies (auto-hides when empty)
Poster grid of completed movie downloads. Tap → reused movie detail view backed by `OfflineMediaMetadata`.

### Section 3: TV Shows (auto-hides when empty)
Poster grid of series that have downloaded episodes. Tap series → season list → episode list. Full hierarchy navigation. All backed by `OfflineMediaMetadata`.

### Section 4: Music (auto-hides when empty)
Album art grid, sectioned by artist name headers. Tap album → track list (playable inline). All backed by `OfflineMediaMetadata`.

---

## 10. Download Initiation UX

| Trigger | Action |
|---|---|
| Download button on **Series** detail | Season picker sheet → enqueue all episodes for selected seasons |
| Download button on **Season** row | Enqueue all episodes in that season |
| Download button on **Episode** row | Enqueue single episode |
| Download button on **Album** detail | Enqueue all tracks |
| Download button on **Track** row | Enqueue single track |
| Download button on **Movie** detail | Enqueue single movie |

All confirmations show estimated size + available space when the server provides file size info.

---

## 11. Deletion

| Action | Behavior |
|---|---|
| Delete a **series** | Confirmation: "Remove Breaking Bad? All 22 episodes (4.7 GB) will be removed." → cascades: all child DownloadItems + groups + offline_metadata + files |
| Delete an **album** | Confirmation: "Remove Abbey Road? All 17 tracks (312 MB) will be removed." → cascades |
| Delete a single **episode/track** | Swipe-to-delete or context menu, no confirmation. If last child in group, clean up the group + parent metadata |
| Delete a **movie** | Confirmation → remove DownloadItem + metadata + files |
| **Re-download** any item | Start completely fresh. No tombstones or history. Server is source of truth — re-downloading fetches fresh metadata |

---

## 12. Queue Management

- Enqueue in natural order: episodes by `episodeNumber`, tracks by `discNumber` then `trackNumber`
- Strict FIFO — no priority system
- Max 3 concurrent downloads (existing `maxConcurrentDownloads`)
- WiFi-only gate checked before starting each new download

---

## 13. Forward Compatibility Rules

The `OfflineMediaMetadata` JSON blob uses these rules to stay forward-compatible:

1. **Every field except identifiers is optional** — missing keys decode as `nil`
2. **Never make a previously-optional field required**
3. **Never rename a coding key**
4. **New fields are always added as optionals**
5. No versioning scheme needed — Swift's default `Codable` behavior for optionals handles it

---

## Implementation Order

1. **Models**: `OfflineMediaMetadata`, `DownloadGroup`, extend `DownloadItem` with `groupId`
2. **Database**: Migration `003_offline_redesign` — new tables + altered `downloads`
3. **Persistence**: `OfflineMetadataRepository`, `DownloadGroupRepository`, `ValueObservation` APIs on `DownloadRepository`
4. **Settings**: `Defaults.Keys.downloadOverCellular` + toggle in `SettingsView`
5. **Download Manager**: Batch enqueue, artwork download, subtitle download, WiFi-only gate, group completion notifications
6. **Image loading**: Local file override in image loading layer
7. **Playback wiring**: Local-first URL resolvers for audio + video + subtitles
8. **UI — Downloads page**: Hybrid layout with all sections
9. **UI — Download buttons**: Season picker sheet, size estimates, per-level download buttons
10. **UI — Deletion**: Cascade delete with confirmations