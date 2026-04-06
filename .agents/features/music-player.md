# Music Player — Feature Plan

> **Status**: Approved design, ready for implementation
> **Scope**: Full-featured music player with feature parity to Apple Music and Spotify — library browsing, full-screen player with lyrics and queue, context menus, and playback features

---

## Overview

Redesign the music player experience in Cove to reach feature parity with Apple Music and Spotify. This covers five major areas:

1. **Music Library Navigation** — expand browsing categories, add discovery shelves
2. **Full-Screen Player** — paged layout (artwork, lyrics, queue) with persistent controls
3. **Context Menus** — consistent long-press actions on every music item throughout the app
4. **Playback Features** — sleep timer, audio quality indicator, favorites
5. **Playlist Management** — full CRUD for playlists

---

## 1. Music Library Navigation

### Current State

`MusicLibraryView` has a segmented picker with 3 sections: **Artists**, **Albums**, **Playlists**. The architecture doc already planned for Songs and Genres but they were never built.

### New Structure

The segmented picker expands to **5 sections**:

| Section | Item Type | API `includeItemTypes` | Existing? |
|---|---|---|---|
| Artists | `MusicArtist` | `MusicArtist` | ✅ `ArtistListView` |
| Albums | `MusicAlbum` | `MusicAlbum` | ✅ `AlbumListView` |
| Songs | `Audio` | `Audio` | ❌ New |
| Playlists | `Playlist` | `Playlist` | ✅ `PlaylistListView` |
| Genres | `Genre` | `Genre` (scoped to music library) | ❌ New |

### Discovery Shelves (Above Picker)

Above the segmented picker, add horizontally-scrolling shelves for curated/dynamic content. These are **not** browsing categories — they're lightweight discovery surfaces.

| Shelf | API Sort | Notes |
|---|---|---|
| **Recently Added** | `SortBy=DateCreated`, `SortOrder=Descending` | Album artwork cards, limit 20 |
| **Most Played** | `SortBy=PlayCount`, `SortOrder=Descending` | Album artwork cards, limit 20 |
| **Recently Played** | `SortBy=DatePlayed`, `SortOrder=Descending` | Album artwork cards, limit 20 |

Each shelf item is an album card. Tapping navigates to `AlbumDetailView`.

All three sorts are supported by the Jellyfin `/Users/{userId}/Items` endpoint. `PlayCount` needs to be added to `SortField` enum.

### Downloaded Filter

A filter toggle ("Downloaded Only") available across all browsing categories. When active, queries are scoped to items present in the local GRDB download store. This is a **client-side filter**, not an API parameter. Useful when offline or when users want to browse only cached content.

### New Views

#### `SongListView`

- Paginated list (`PagedCollectionLoader<MediaItem>`, 40 per page)
- `includeItemTypes: ["Audio"]`, sorted by name ascending (default)
- Each row: track title, artist name, duration, album art thumbnail (40×40)
- Tapping a song plays it and auto-fills the queue with surrounding songs (Apple Music behavior)
- Support sort options: Name, Date Added, Artist, Album
- "Shuffle All" button in the toolbar

#### `GenreListView`

- Fetches genres scoped to the music library via API approach 1: `includeItemTypes: ["Genre"]`, `parentId: musicLibraryId`
- Returns genre items with names and item counts
- Simple list of genre names with item count
- Tapping a genre navigates to `GenreDetailView`
- Note: genres are also embedded as string arrays on albums/tracks (`BaseItemDto`) — used for filter chips and display, same underlying data accessed differently

#### `GenreDetailView`

- Navigation title: genre name
- Album grid fetched with `getItems(includeItemTypes: ["MusicAlbum"], genres: [genreName])`
- Same `LazyVGrid` layout as `AlbumListView`
- Sort options: Name, Year, Date Added, Artist (same as album list)
- Tapping an album navigates to `AlbumDetailView`
- **No songs section** within genre detail for v1 — albums are the primary browsing unit
- **No artists section** within genre detail for v1 — users can browse albums and tap through to artists

#### `PlaylistDetailView`

- Same structure as `AlbumDetailView` — header with artwork, title, metadata, track list
- Play and Shuffle buttons
- Track rows with reorder and delete support (for user-owned playlists)
- Currently `PlaylistListView` rows are display-only with no navigation — wire up `NavigationLink(value: playlist)`

---

## 2. Full-Screen Player Redesign

### Current State

`AudioPlayerView` is a modal sheet with artwork, track info, scrubber, play/pause/next/prev, shuffle, repeat. `QueueView` is presented as a **separate sheet** on top of the player. No lyrics UI exists.

### New Architecture: Paged Player

The player sheet becomes a **paged container** with three swipeable pages and persistent controls. This matches Apple Music's player model.

#### Layout (top to bottom)

```
┌─────────────────────────────────────────┐
│  ○ Drag indicator                       │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │  PAGE 1: Artwork                  │  │  ← swipeable area
│  │  PAGE 2: Lyrics                   │  │
│  │  PAGE 3: Queue                    │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Track Title                    ♡  ···  │  ← persistent
│  Artist Name                            │
│                                         │
│  ● ○ ○  (page indicator dots)           │  ← persistent
│                                         │
│   advancement──────────○──────────────   │  ← persistent
│  0:42                          -2:18    │
│                                         │
│  🔀       ◁◁      ▶︎      ▷▷       🔁   │  ← persistent
│                                         │
│  🔊───────────○──────────── AirPlay     │  ← persistent
│                                         │
│  [Lyrics] [Queue]   [Sleep] [Quality]   │  ← persistent toolbar
└─────────────────────────────────────────┘
```

#### Persistent Section (always visible across all pages)

| Element | Details |
|---|---|
| **Track info** | Title (`.title2.bold()`), artist name (`.title3`, secondary). Single-line each. Animated on track change. |
| **Favorite button** | Heart icon. Toggles `isFavorite` via Jellyfin API. Filled when active. |
| **Context menu (…)** | Same actions as the track context menu (see §4). |
| **Page indicator dots** | Three dots showing current page. Standard `TabView` page indicator. |
| **Scrubber** | `Slider` with elapsed time (left) and remaining time with `-` prefix (right). Monospaced digit captions. Seeks on release. |
| **Playback controls** | Previous / Play-Pause / Next. Previous/Next disabled when unavailable. Play-Pause is large (56pt). |
| **Shuffle button** | Accent-colored when active. |
| **Repeat button** | Cycles: off → repeat all → repeat one. Accent-colored when active. SF Symbol changes per mode. |
| **Volume slider** | `MPVolumeView` for system volume control with integrated AirPlay route picker. On macOS, use `AVRoutePickerView`. |
| **Bottom toolbar** | Shortcut buttons for Lyrics (jumps to page 2), Queue (jumps to page 3), Sleep Timer, Audio Quality badge. |

#### Page 1: Now Playing (Artwork)

- Large album artwork, max 600×600, 12pt corner radius, drop shadow
- Animated transition on track change (scale + fade)
- **Background:** Dominant color gradient — see §2a below for full details

#### Page 2: Lyrics

- **Synced lyrics** (when `LyricLine.startTime` is non-nil):
  - Current line: vertically centered, full opacity, larger/bolder font
  - Past/future lines: dimmed (secondary color), standard font
  - Auto-scrolls to keep current line centered
  - **Tapping a line seeks playback to that line's timestamp**
  - If user manually scrolls, auto-scroll pauses for ~3 seconds, then resumes
- **Unsynced lyrics** (when `startTime` is nil for all lines):
  - Static scrollable text, no highlight, no tap-to-seek
  - Full lyrics displayed as a block of text
- **No lyrics available:**
  - Centered empty state: music note icon + "Lyrics not available" text
  - Styled to match the page's color theme (not a harsh `ContentUnavailableView`)
  - **Page is always present in the pager** — never dynamically removed (preserves page indices and muscle memory)
- **Background:** Same dominant-color gradient as Page 1

#### Page 3: Queue

- **Header row:** "Playing From *Album Name*" or "Playing From *Playlist Name*" — shows the source context from `PlayQueue.context` (see §2c). Tappable to navigate: dismisses the player, sets `appState.selectedTab` and appends the route to the corresponding `NavigationPath` (see §2b).
- **Now Playing row:** Current track with accent color background tint (`.opacity(0.08)`), animated speaker icon (`speaker.wave.2.fill` with `.symbolEffect(.variableColor.iterative)` when playing), artwork thumbnail (44×44), title, artist. **Not** deletable or reorderable.
- **Up Next section:**
  - Section header: "Up Next · *N* tracks" with a **"Clear"** button (clears all upcoming tracks, with `.confirmationDialog` confirmation)
  - Compact rows (44pt height): artwork thumbnail (40×40), title, artist, duration
  - Swipe-to-delete on individual tracks
  - Long-press drag to reorder
  - **No permanent edit mode** — remove `.environment(\.editMode, .constant(.active))`, use standard iOS gestures instead
  - The list scrolls independently within the page area
- **Empty state:** When no tracks in queue, `ContentUnavailableView` with "Queue Empty" and `music.note.list` icon
- **No "add to queue" from this page** — adding to queue happens via context menus elsewhere in the app. The queue page is for viewing and rearranging only.
- **No playback history** — queue shows current track + up next only. History is deferred.

### Page Navigation

- Implemented as a `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` (custom page dots for styling control)
- Toolbar buttons for Lyrics and Queue act as shortcuts — tapping them programmatically switches to the corresponding page via the `@State` selection binding
- Horizontal swipe gesture between pages is the primary navigation method
- `@State private var currentPage: PlayerPage = .artwork` enum drives the selection

### Implementation Notes

- `AudioPlayerView` becomes the paged container
- Current `QueueView` content moves inline as Page 3
- New `LyricsView` created as Page 2
- Persistent controls extracted into a `PlayerControlsView` component
- The `NowPlayingBar` (mini player) remains unchanged — it still expands to the full player sheet on tap

---

### 2a. Dominant Color Extraction

The player background uses a gradient derived from the current track's album artwork. This is a critical visual feature that touches every page.

#### Algorithm (DIY, zero dependencies)

1. Downsample the `CGImage` to 10×10 (100 pixels) using `CGContext` — essentially free
2. Read all pixel RGBA values
3. Sort pixels into HSB buckets, pick the top 2-3 by frequency
4. Filter out near-white (brightness > 0.95) and near-black (brightness < 0.05) — they make bad backgrounds
5. Calculate luminance of the dominant color: `0.299*R + 0.587*G + 0.114*B`

Total implementation: ~80 lines in `DominantColorExtractor.swift`, no external dependencies.

#### Gradient Rendering

- Top-to-bottom `LinearGradient` with 2 stops:
  - **Top:** Dominant color at ~70% opacity
  - **Bottom:** Dominant color darkened (shifted toward black) at ~90% opacity
- All three pages share the same gradient — swiping between them is seamless (background stays, content changes)
- Gradient renders behind `.ultraThinMaterial`, giving a tinted frosted-glass look

#### Text & Control Adaptation

- If luminance > 0.5 (light background): apply `.colorScheme(.dark)` override — all system controls, SF Symbols, and text automatically use dark variants
- If luminance ≤ 0.5 (dark background): apply `.colorScheme(.light)` override
- No per-element color styling needed — the `ColorScheme` override handles everything

#### Track Change Transition

- Animate gradient change with slow ease-in-out (~0.6s)
- Extract colors from the *next* track's artwork during the gapless preload window, so the gradient is ready the instant the track changes
- No flash of old color or jarring cut

#### Caching

- Cache extracted colors keyed by `albumId` (not `trackId` — all tracks on the same album share artwork)
- Extract once per album, reuse across tracks and page swipes
- Cache lives in memory only — no persistence needed

#### Fallback

- When artwork is unavailable: fall back to a neutral dark gradient (system background colors)
- Essentially the current player appearance — no color extraction needed

---

### 2b. Navigation Architecture (Controlled NavigationPaths)

The player needs to dismiss and navigate to destinations in the app (e.g., "Go to Album", "Playing From" tap). This requires controlled navigation stacks.

#### Changes to `AppState`

Promote `selectedTab` and per-tab navigation paths from local `@State` to `AppState`:

```swift
// On AppState:
var selectedTab: AppTab = .home
var navigationPaths: [AppTab: NavigationPath] = [
    .home: NavigationPath(),
    .music: NavigationPath(),
    .movies: NavigationPath(),
    .tvShows: NavigationPath(),
    .downloads: NavigationPath(),
    .search: NavigationPath(),
    .settings: NavigationPath(),
]
```

#### Changes to `AppShellView`

Each tab's `NavigationStack` becomes controlled:

```swift
NavigationStack(path: $appState.navigationPaths[.music]!) {
    tab.destination(appState: appState)
        .navigationTitle(tab.title)
        .withNavigationDestinations()
}
```

`selectedTab` binds to `appState.selectedTab` instead of local state.

#### Navigation from Player

All navigation actions inside the player follow the same pattern — mutate path, then dismiss:

```swift
func navigateToAlbum(_ album: Album) {
    appState.selectedTab = .music
    appState.navigationPaths[.music]?.append(album)
    dismiss()
}
```

No intermediate `PendingNavigation` enum, no `.onChange` observers. The `NavigationPath` *is* the state — SwiftUI picks it up automatically after dismiss.

#### Rule

**All navigation actions dismiss the player first, then navigate in the app's root context. No navigation happens inside the player modal.** The player stays purely a player — no browsing.

This applies to:
- "Playing From *Album Name*" tap on the queue page
- "Go to Album" from the context menu (…)
- "Go to Artist" from the context menu (…)

#### Deep Linking Bonus

This architecture also future-proofs deep linking — a `DeepLinkRouter` just sets `selectedTab` and appends to the right path. No additional infrastructure needed.

---

### 2c. Play Context (Queue Source Tracking)

The queue page shows "Playing From *Abbey Road*" — the queue needs to know what the user started playing from.

#### New Types

```swift
public struct PlayContext: Sendable, Equatable {
    public let title: String          // "Abbey Road", "Road Trip Mix", "All Songs"
    public let type: PlayContextType
    public let id: ItemID?            // albumId, playlistId, artistId — for navigation
}

public enum PlayContextType: String, Sendable {
    case album, playlist, artist, genre, songs, radio, unknown
}
```

#### Changes to `PlayQueue`

- Add `public private(set) var context: PlayContext?`
- Extend `load(tracks:startingAt:context:)` to accept the optional context

#### Call Sites

Every place that starts playback passes the context:

| Call Site | Context |
|---|---|
| `AlbumDetailView.playAllTracks()` | `PlayContext(title: album.title, type: .album, id: album.id)` |
| `PlaylistDetailView` play/shuffle | `PlayContext(title: playlist.name, type: .playlist, id: playlist.id)` |
| `ArtistDetailView` play/shuffle | `PlayContext(title: artist.name, type: .artist, id: artist.id)` |
| `GenreDetailView` play/shuffle | `PlayContext(title: genreName, type: .genre, id: nil)` |
| Songs list shuffle all | `PlayContext(title: "All Songs", type: .songs, id: nil)` |
| Instant Mix (radio) | `PlayContext(title: "Radio · \(seedName)", type: .radio, id: seedItemId)` |

#### Queue Modification Rule

When the queue is modified via "Play Next" / "Play Later" additions mixing multiple sources, keep the **original** context from when playback started — don't overwrite it on queue modifications.

---

## 3. Now Playing Bar

### Current State

`NowPlayingBar` shows artwork (48×48), track title, artist name, and a play/pause button. It's functional but minimal.

### Enhancements

| Enhancement | Details |
|---|---|
| **Progress indicator** | Thin progress bar (2pt) along the top edge of the bar, showing playback progress. No interaction — just visual feedback. |
| **Next track button** | Add a forward skip button next to play/pause. Two buttons is the sweet spot for the mini bar (Apple Music does play/pause + next). |
| **Swipe-up gesture** | Optional: swipe up on the bar to expand to full player. Complement to the existing tap. |

---

## 4. Context Menus

Consistent long-press context menus on every tappable music item throughout the app. These are the connective tissue of the music experience.

### Track Context Menu

| Action | Icon | Behavior |
|---|---|---|
| Play Next | `text.line.first.and.arrowforward` | Inserts track after current in queue via `queue.addNext(_:)` |
| Play Later | `text.line.last.and.arrowforward` | Appends track to end of queue via `queue.addToEnd(_:)` |
| Start Radio | `dot.radiowaves.left.and.right` | Fetches instant mix seeded from this track, replaces queue, starts playing (see §4c) |
| Add to Playlist… | `text.badge.plus` | Presents playlist picker sheet (list of existing playlists + "New Playlist" button) |
| Go to Album | `square.stack` | Navigates to `AlbumDetailView` for the track's `albumId` |
| Go to Artist | `music.mic` | Navigates to `ArtistDetailView` for the track's `artistId` |
| Favorite / Unfavorite | `heart` / `heart.fill` | Toggles `isFavorite` via Jellyfin API. Filled icon when favorited. |
| Download / Remove Download | `arrow.down.circle` / `checkmark.circle.fill` | Toggles offline availability for the single track |

### Album Context Menu

| Action | Icon | Behavior |
|---|---|---|
| Play | `play.fill` | Plays all tracks from track 1 |
| Shuffle | `shuffle` | Plays all tracks in shuffled order |
| Play Next | `text.line.first.and.arrowforward` | Inserts all album tracks after current in queue |
| Play Later | `text.line.last.and.arrowforward` | Appends all album tracks to end of queue |
| Start Radio | `dot.radiowaves.left.and.right` | Fetches instant mix seeded from this album, replaces queue, starts playing (see §4c) |
| Add to Playlist… | `text.badge.plus` | Adds all album tracks to a playlist |
| Go to Artist | `music.mic` | Navigates to `ArtistDetailView` for the album's `artistId` |
| Favorite / Unfavorite | `heart` / `heart.fill` | Toggles `isFavorite` on the album item |
| Download / Remove Download | `arrow.down.circle` / `checkmark.circle.fill` | Album-level download (existing functionality) |

### Artist Context Menu

| Action | Icon | Behavior |
|---|---|---|
| Play | `play.fill` | Plays all artist tracks (fetch all, play from first) |
| Shuffle | `shuffle` | Shuffles all artist tracks |
| Start Radio | `dot.radiowaves.left.and.right` | Fetches instant mix seeded from this artist, replaces queue, starts playing (see §4c) |
| Favorite / Unfavorite | `heart` / `heart.fill` | Toggles `isFavorite` on the artist item |

### Playlist Context Menu

| Action | Icon | Behavior |
|---|---|---|
| Play | `play.fill` | Plays playlist from track 1 |
| Shuffle | `shuffle` | Plays playlist in shuffled order |
| Play Next | `text.line.first.and.arrowforward` | Inserts all playlist tracks after current in queue |
| Play Later | `text.line.last.and.arrowforward` | Appends all playlist tracks to end of queue |
| Rename… | `pencil` | Inline rename via alert with text field (Jellyfin API: `POST /Items/{id}`) |
| Delete Playlist | `trash` | Destructive action with `.confirmationDialog`. Jellyfin API: `DELETE /Items/{id}` |
| Download / Remove Download | `arrow.down.circle` / `checkmark.circle.fill` | Playlist-level download |

### Shared Components

#### Playlist Picker Sheet

Presented by "Add to Playlist…" actions. Contains:
- Search bar to filter playlists
- "New Playlist" button at the top (creates playlist and adds tracks in one flow)
- List of existing playlists with artwork thumbnails
- Tapping a playlist adds the track(s) and dismisses with a confirmation toast

This is a reusable `PlaylistPickerSheet` view used from track, album, and playlist context menus.

### Implementation Notes

- Build context menus as SwiftUI `View` modifiers (e.g., `.trackContextMenu(track:)`, `.albumContextMenu(album:)`) for consistent reuse
- "Play Next" and "Play Later" show a toast confirming the action (see §4a)
- Actions that require fetching tracks (e.g., "Play All" on an artist) should show a loading indicator briefly
- "Go to Album" and "Go to Artist" inside the player dismiss the player and navigate via `AppState.navigationPaths` (see §2b)
- "Add to Playlist…" presents `PlaylistPickerSheet` as a sheet (see §4b)
- "Start Radio" fetches instant mix and replaces the queue (see §4c)

---

### 4a. Toast / Snackbar Feedback

Every queue or playlist action from a context menu needs visual confirmation. Without feedback, users wonder if they actually tapped the right thing.

#### Design

- Small capsule shape, `.regularMaterial` background
- Appears above the Now Playing bar (or at the bottom of the screen if no bar is showing)
- SF Symbol icon + short text: "✓ Playing Next" / "✓ Added to Up Next" / "✓ Added to *Playlist Name*"
- Slides in from bottom, auto-dismisses after 2 seconds
- Combined with a success haptic (`UINotificationFeedbackGenerator.success`) on iOS
- Tappable to dismiss early, but no other interaction
- Only one toast at a time — new toast replaces the current one

#### Implementation

- Reusable `ToastView` component driven by `AppState`
- Any view can trigger: `appState.showToast("Playing Next", icon: "text.line.first.and.arrowforward")`
- Rendered as an overlay in `AppShellView` (above the Now Playing bar, below sheets)
- Used by: context menu actions, playlist additions, download actions

---

### 4b. Playlist Picker Sheet

Presented by "Add to Playlist…" actions from any context menu.

#### Layout

- Presented as a `.sheet` with `.medium` and `.large` detents (starts at medium, expandable)
- **Top:** "Add to Playlist" title + "New Playlist" button in the toolbar
- **Search bar** below the title to filter playlists by name (client-side filtering of already-fetched list)
- **Playlist list:** Each row shows playlist artwork (44×44), name, track count

#### Interaction

- Tapping a row adds the track(s) immediately, dismisses the sheet, and shows a toast: "✓ Added to *Playlist Name*"
- API call batches all track IDs into a single `POST /Playlists/{id}/Items?Ids={csv}`

#### "New Playlist" Flow

1. Tapping "New Playlist" presents an alert with a text field for the playlist name
2. On confirm: creates the playlist via API, adds the pending track(s) to it, dismisses everything, shows toast: "✓ Added to *New Playlist Name*"
3. If creation fails, show an error alert and keep the sheet open

#### Multi-Track Support

The sheet accepts `tracks: [Track]` — works the same whether adding 1 track from a track context menu or 14 tracks from an album context menu.

#### State Management

- Fetches playlists on appear (calls `appState.provider.playlists()`)
- Search filtering is client-side (filter the already-fetched list by name)

---

### 4c. Instant Mix (Radio)

Jellyfin has a dedicated `/Items/{id}/InstantMix` endpoint that generates a mix based on a seed track, album, or artist. This powers a "Start Radio" context menu action.

#### Where It Appears

| Item Type | Action Label | API Call |
|---|---|---|
| Track | "Start Radio" | `GET /Items/{trackId}/InstantMix?UserId={userId}&Limit=50` |
| Album | "Start Radio" | `GET /Items/{albumId}/InstantMix?UserId={userId}&Limit=50` |
| Artist | "Start Radio" | `GET /Items/{artistId}/InstantMix?UserId={userId}&Limit=50` |

Not on playlists — playlists are already user-curated, "radio from a playlist" doesn't fit.

#### Behavior

1. Fetch instant mix tracks from API (up to 50 tracks, ~3 hours of music)
2. **Replace the current queue** with the mix results (new playback session, same as tapping "Play" on an album)
3. Start playing from the first track
4. Set `PlayContext(title: "Radio · \(seedItemName)", type: .radio, id: seedItemId)`
5. Show toast: "✓ Radio started"

#### No Auto-Refill

When the radio queue runs out, playback stops. No automatic refilling for v1. Fetching more tracks would require tracking what's already been played to avoid repeats and managing an infinite queue — that's v2 territory alongside autoplay.

#### No Dedicated UI

Radio is purely a context menu action. No dedicated "Radio" tab, section, or saved radio stations.

---

## 5. Playback Features

### Sleep Timer

A countdown timer that pauses playback when it reaches zero.

**Options:** 5 min, 10 min, 15 min, 30 min, 45 min, 1 hour, End of Track.

**Implementation:**
- Add `sleepTimer` state to `AudioPlaybackManager`: `sleepTimerEndDate: Date?` and `sleepTimerMode: SleepTimerMode?`
- `SleepTimerMode` enum: `.minutes(Int)`, `.endOfTrack`
- For timed modes: schedule with a `Task.sleep` that checks periodically (every second) and pauses playback when `Date.now >= sleepTimerEndDate`
- For `.endOfTrack`: hook into the track-end handler to pause instead of advancing
- The sleep timer button in the player toolbar shows remaining time when active (e.g., "23m") and accent-colored

**UI:** Tapping the sleep timer button presents a menu/action sheet with duration options. If a timer is active, show the remaining time and a "Cancel Timer" option.

### Audio Quality Indicator

Display the codec and quality information for the currently playing track.

**Implementation:**
- `Track.codec` already exists (e.g., `"flac"`, `"mp3"`, `"aac"`, `"opus"`)
- Display a small badge in the player toolbar: "FLAC", "MP3", "AAC", etc.
- For lossless formats (FLAC, ALAC, WAV), show with a distinct style (e.g., accent-colored text or a "Lossless" label)
- Tapping the badge shows a popover with full details: codec, bitrate (if available), sample rate (if available)

**Model changes:** Consider adding `bitRate: Int?` and `sampleRate: Int?` to `Track`. These are available from Jellyfin's `MediaStream` data in the `BaseItemDto`.

### Favorite Button

- Heart icon in the persistent player controls, next to track title
- Toggles `isFavorite` via Jellyfin API: `POST /Users/{userId}/FavoriteItems/{itemId}` (add) or `DELETE /Users/{userId}/FavoriteItems/{itemId}` (remove)
- Immediate optimistic UI update with rollback on failure
- Animated fill transition on tap (scale + bounce)

---

## 6. Playlist Management (CRUD)

### Current State

`PlaylistListView` fetches and displays playlists but rows are display-only (no `NavigationLink`, no CRUD).

### New Capabilities

| Operation | API Endpoint | UI Trigger |
|---|---|---|
| **Create** | `POST /Playlists` | "New Playlist" button in `PlaylistListView` toolbar + inside `PlaylistPickerSheet` |
| **Read** | `GET /Users/{userId}/Items` (type: Playlist) + `GET /Playlists/{id}/Items` | `PlaylistListView` + `PlaylistDetailView` |
| **Update (rename)** | `POST /Items/{id}` with new `Name` | Context menu "Rename…" or inline edit in `PlaylistDetailView` |
| **Update (reorder)** | `POST /Playlists/{id}/Items` with new item order | Drag-to-reorder in `PlaylistDetailView` |
| **Update (add tracks)** | `POST /Playlists/{id}/Items?Ids={trackIds}` | "Add to Playlist…" context menu action |
| **Update (remove tracks)** | `DELETE /Playlists/{id}/Items?EntryIds={entryIds}` | Swipe-to-delete in `PlaylistDetailView` |
| **Delete** | `DELETE /Items/{id}` | Context menu "Delete Playlist" with confirmation |

### Create Playlist Flow

1. User taps "New Playlist" (either from toolbar or picker sheet)
2. Alert/sheet with text field for playlist name
3. Optional: if triggered from "Add to Playlist…", pre-populate with the tracks being added
4. API call creates the playlist, then adds tracks if any
5. Playlist list refreshes to show the new playlist

---

## 7. Sorting & Filtering

### Sort Options per Category

| Category | Available Sorts | Default |
|---|---|---|
| Artists | Name, Date Added | Name ↑ |
| Albums | Name, Date Added, Artist, Year | Name ↑ |
| Songs | Name, Date Added, Artist, Album | Name ↑ |
| Playlists | Name, Date Added | Name ↑ |
| Genres | Name | Name ↑ |

### Filter Options

| Filter | Scope | Implementation |
|---|---|---|
| Favorites Only | All categories | API: `isFavorite=true` |
| Downloaded Only | All categories | Client-side: intersect with GRDB download store |
| Genre | Albums, Songs | API: `Genres={name}` |
| Year | Albums | API: `Years={year}` |

### Sort UI

- Toolbar button in the top-right (SF Symbol: `arrow.up.arrow.down`)
- Tapping reveals a `Menu` with sort options for the current category
- Currently active sort has a checkmark
- Tapping a sort option applies it immediately (no confirm button)
- **Tapping the already-active sort toggles the order** — e.g., "Name ↑" flips to "Name ↓"
- Matches Apple's standard sort pattern (Files, Music, etc.)

### Filter UI

- Horizontal `ScrollView(.horizontal)` of pill-shaped buttons
- Positioned **between** the discovery shelves and the segmented picker
- **Universal filters** (appear on all categories):
  - **Favorites** — accent-colored (filled) when active, `.secondary` (outline) when inactive
  - **Downloaded** — same styling
- **Contextual filters** (appear only on relevant categories):
  - **Genre chips** — appear on Albums and Songs. Tapping shows a menu/popover to pick a genre, then a chip with the genre name appears with a "✕" to clear.
  - **Year chips** — appear on Albums only. Same pattern.
- Multiple filters can be active simultaneously — they AND together

### Sort/Filter State Persistence

No persistence across app launches. Reset to defaults (Name ascending, no filters) on each launch. Users of music apps generally browse fresh each session. Defer persistence.

### Model Changes

Add `SortField.playCount` to support "Most Played" sorting:

```swift
public enum SortField: String, Codable, Sendable {
    // ... existing cases ...
    case playCount
}
```

Map to Jellyfin API `SortBy=PlayCount`.

---

## 8. Audio Session Behavior

### Ducking

No changes needed. Cove uses `.playback` category with no special options (already implemented). The system handles ducking automatically based on what the interrupting app requests (e.g., Maps navigation prompts). The `.duckOthers` option is set by the *interrupting* app, not by Cove.

### Video/Audio Conflict

When `VideoPlaybackManager` starts playback while music is playing:

1. `VideoPlaybackManager` **pauses** `AudioPlaybackManager` before starting video playback
2. When the video player is dismissed, music does **not** auto-resume
3. The Now Playing bar still shows the paused music track — user can tap play to resume manually
4. This avoids jarring audio overlap and matches Apple's behavior

### Phone Call Interruption

Already handled by the existing `AVAudioSession.interruptionNotification` observer. When the interruption ends with `shouldResume = true`, `resume()` is called. No changes needed.

### Queue End Behavior

When `PlayQueue` reaches the last track and repeat mode is `.off`, playback stops. The player shows the last track's artwork in a paused state. No autoplay of similar tracks for v1 — Jellyfin's "Similar Items" endpoint depends on metadata quality which varies across self-hosted libraries. Autoplay is a good v2 feature once the core player is solid.

---

## 9. Downloads for New Music Features

### Download Scope

| Surface | Downloadable? | Behavior |
|---|---|---|
| **Album detail** | ✅ Already works | Downloads all tracks in the album |
| **Playlist detail** | ✅ New | Downloads all tracks in the playlist |
| **Individual track** (context menu) | ✅ New | Downloads a single track, stored under `Downloads/{serverId}/track/{itemId}/` |
| **Artist detail** | ❌ No | Too broad — could be hundreds of tracks. Users download specific albums. |
| **Genre detail** | ❌ No | Too broad. |
| **Songs list** | ❌ No | No "download all" button. Individual tracks downloadable via context menu. |

### Playlist Download Specifics

- Creates a `DownloadGroup` for the playlist (same pattern as album downloads in the downloads spec)
- If a track in the playlist is already downloaded (from an album download), **skip it** — don't re-download
- Tracks are stored individually, keyed by `trackId` — natural deduplication at the file level

### Deduplication & Deletion

No reference counting for v1. Each download is independent, but files are stored once per `trackId`:

- If a track exists in both a downloaded album and a downloaded playlist, it's stored once
- Deleting an album download: **don't delete the file** if another `DownloadItem` (e.g., from a playlist group) still references the same `trackId`
- The `DownloadManager` checks "does any other `DownloadItem` reference this `trackId`?" before deleting the physical file
- Only delete the file when *all* groups referencing it are removed

---

## 10. Jellyfin API Additions

New endpoints/parameters needed beyond what `JellyfinAPIClient` currently supports:

| Capability | Endpoint | Notes |
|---|---|---|
| **Lyrics** | `GET /Audio/{itemId}/Lyrics` | Returns synced or unsynced lyrics. Already defined in `MusicProvider.lyrics()` but implementation returns `nil`. |
| **Toggle favorite** | `POST /Users/{userId}/FavoriteItems/{itemId}` (add) / `DELETE` (remove) | New method on `JellyfinAPIClient` |
| **Create playlist** | `POST /Playlists` | Body: `{ Name, Ids[], MediaType: "Audio" }` |
| **Add to playlist** | `POST /Playlists/{id}/Items?Ids={csv}` | Append tracks |
| **Remove from playlist** | `DELETE /Playlists/{id}/Items?EntryIds={csv}` | Remove specific entries |
| **Reorder playlist** | `POST /Playlists/{id}/Items` | Set new item order |
| **Rename item** | `POST /Items/{id}` | Body: `{ Name: "new name" }` |
| **Delete item** | `DELETE /Items/{id}` | Destructive, used for playlist deletion |
| **Get playlist items** | `GET /Playlists/{id}/Items?UserId={userId}` | Fetch tracks in a playlist |
| **Instant mix** | `GET /Items/{itemId}/InstantMix?UserId={userId}&Limit=50` | Returns mix tracks seeded from a track, album, or artist. New method on `JellyfinAPIClient`. |
| **Genres (scoped)** | `GET /Users/{userId}/Items?IncludeItemTypes=Genre&ParentId={musicLibraryId}` | Already works with existing `getItems()` |

---

## 11. Model Changes Summary

### `Track` — new optional fields

```swift
public struct Track: Identifiable, Codable, Hashable, Sendable {
    // ... existing fields ...
    public let bitRate: Int?         // e.g., 320000 (bps), 1411000 for CD-quality
    public let sampleRate: Int?      // e.g., 44100, 96000
    public let channelCount: Int?    // e.g., 2 (stereo), 6 (5.1)
    public let genres: [String]?     // genre tags on the track
    public let userData: UserData?   // favorite status, play count, etc.
}
```

### `Album` — new optional fields

```swift
public struct Album: Identifiable, Codable, Hashable, Sendable {
    // ... existing fields ...
    public let userData: UserData?   // favorite status
    public let genres: [String]?     // all genres on the album
    public let dateAdded: Date?      // for "Recently Added" sorting
}
```

### `Artist` — new optional fields

```swift
public struct Artist: Identifiable, Codable, Hashable, Sendable {
    // ... existing fields ...
    public let userData: UserData?   // favorite status
    public let genres: [String]?     // artist genres
}
```

### `Playlist` — new optional fields

```swift
public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    // ... existing fields ...
    public let userData: UserData?   // favorite status
    public let dateAdded: Date?      // for sorting
}
```

### New Enums

```swift
public enum SleepTimerMode: Sendable, Equatable {
    case minutes(Int)  // 5, 10, 15, 30, 45, 60
    case endOfTrack
}

public enum PlayerPage: Int, CaseIterable {
    case artwork = 0
    case lyrics = 1
    case queue = 2
}

public enum PlayContextType: String, Sendable {
    case album, playlist, artist, genre, songs, unknown
}
```

### New Structs

```swift
public struct PlayContext: Sendable, Equatable {
    public let title: String          // "Abbey Road", "Road Trip Mix", "All Songs"
    public let type: PlayContextType
    public let id: ItemID?            // albumId, playlistId, artistId — for navigation
}
```

---

## 12. New Files

| File | Module | Purpose |
|---|---|---|
| `SongListView.swift` | Cove (UI/Music) | Browse all songs |
| `GenreListView.swift` | Cove (UI/Music) | Browse genres |
| `GenreDetailView.swift` | Cove (UI/Music) | Albums in a genre |
| `PlaylistDetailView.swift` | Cove (UI/Music) | Playlist tracks with CRUD |
| `PlaylistPickerSheet.swift` | Cove (UI/Music) | Shared "Add to Playlist" sheet |
| `LyricsView.swift` | Cove (UI/Player) | Synced/unsynced lyrics page |
| `PlayerControlsView.swift` | Cove (UI/Player) | Extracted persistent controls |
| `DominantColorExtractor.swift` | CoveUI | CGImage color extraction utility |
| `TrackContextMenu.swift` | Cove (UI/Shared) | Reusable track context menu modifier |
| `AlbumContextMenu.swift` | Cove (UI/Shared) | Reusable album context menu modifier |
| `ArtistContextMenu.swift` | Cove (UI/Shared) | Reusable artist context menu modifier |
| `PlaylistContextMenu.swift` | Cove (UI/Shared) | Reusable playlist context menu modifier |
| `SleepTimerManager.swift` | PlaybackEngine | Sleep timer logic |
| `MusicDiscoveryShelf.swift` | Cove (UI/Music) | Horizontal scrolling shelf component |

| `ToastView.swift` | Cove (UI/Shared) | Reusable toast/snackbar feedback component |

## 13. Modified Files

| File | Changes |
|---|---|
| `AudioPlayerView.swift` | Rewrite as paged container with `TabView(.page)`, persistent controls, color extraction |
| `NowPlayingBar.swift` | Add progress bar (2pt, top edge), next track button |
| `QueueView.swift` | Move inline as player page 3, remove sheet presentation, remove permanent edit mode, add "Playing From" header with `PlayContext`, add "Clear Up Next" |
| `MusicLibraryView.swift` | Add Songs and Genres to `MusicSection` enum, add discovery shelves above picker, add sort/filter UI |
| `PlaylistListView.swift` | Wire up `NavigationLink`, add "New Playlist" toolbar button, add context menus |
| `AlbumDetailView.swift` | Add context menus on tracks, add "Play Next"/"Play Later" actions, pass `PlayContext` on play |
| `AlbumListView.swift` | Add context menus on album cards |
| `ArtistListView.swift` | Add context menus on artist cards |
| `ArtistDetailView.swift` | Add context menus on album cards, pass `PlayContext` on play |
| `AudioPlaybackManager.swift` | Add sleep timer state + logic, add favorite toggle method, pause when video starts |
| `PlayQueue.swift` | Add `context: PlayContext?` property, extend `load(tracks:startingAt:context:)` |
| `Track.swift` | Add `bitRate`, `sampleRate`, `channelCount`, `genres`, `userData` fields |
| `Album.swift` | Add `userData`, `genres`, `dateAdded` fields |
| `Artist.swift` | Add `userData`, `genres` fields |
| `Playlist.swift` | Add `userData`, `dateAdded` fields |
| `SortOptions.swift` | Add `SortField.playCount` case |
| `JellyfinAPIClient.swift` | Add lyrics, favorite toggle, playlist CRUD endpoints |
| `JellyfinServerProvider.swift` | Implement lyrics, favorites, playlist operations |
| `JellyfinMapper.swift` | Map new fields (bitRate, sampleRate, userData, genres) from `BaseItemDto` |
| `MusicProvider.swift` | Add playlist CRUD, favorite toggle, and instant mix to protocol |
| `AppState.swift` | Add `selectedTab`, `navigationPaths: [AppTab: NavigationPath]`, toast state |
| `AppShellView.swift` | Bind to `appState.selectedTab`, use controlled `NavigationStack(path:)` per tab, add `ToastView` overlay |
| `VideoPlaybackManager.swift` | Pause `AudioPlaybackManager` before starting video playback |

---

## 14. Decisions Log

| # | Decision | Choice |
|---|---|---|
| 1 | Music library categories | 5 sections: Artists, Albums, Songs, Playlists, Genres |
| 2 | Discovery surfaces | Horizontal shelves above picker: Recently Added, Most Played, Recently Played |
| 3 | "Downloaded Music" category | No — use a filter toggle across all categories instead |
| 4 | Full-screen player model | 3-page swipeable container (Artwork, Lyrics, Queue) with persistent controls |
| 5 | Queue presentation | Inline as player page 3 — not a separate sheet |
| 6 | Lyrics synced scrolling | Auto-scroll with centered highlight, tap-to-seek, 3s pause on manual scroll |
| 7 | Lyrics background | Dominant color gradient extracted from album artwork |
| 8 | Lyrics unavailable | Static empty state on a page that's always present in the pager |
| 9 | Queue "Playing From" | Header row showing source via `PlayContext`, tappable to dismiss + navigate |
| 10 | Queue "Clear Up Next" | Button in Up Next section header with confirmation dialog |
| 11 | Queue history | Deferred — queue shows current track + up next only |
| 12 | Queue edit mode | Standard swipe-to-delete + long-press drag — no permanent edit mode |
| 13 | Volume control | `MPVolumeView` with integrated AirPlay route picker in persistent controls |
| 14 | Sleep timer | Countdown timer on `AudioPlaybackManager`, options: 5/10/15/30/45/60 min + end of track |
| 15 | Audio quality badge | Codec label in player toolbar, popover with details on tap |
| 16 | Crossfade | Deferred — conflicts with AVQueuePlayer gapless playback approach |
| 17 | Context menus | Full action set on tracks, albums, artists, playlists (see §4) |
| 18 | Playlist CRUD | Full create/read/update/delete via Jellyfin API |
| 19 | "Add to Playlist" | Shared `PlaylistPickerSheet` with search, existing playlists, and "New Playlist" (see §4b) |
| 20 | Sorting | Per-category sort options via toolbar menu, tap active sort to toggle order |
| 21 | Filtering | Favorites/Downloaded universal chips + contextual Genre/Year chips, AND logic |
| 22 | Dominant color extraction | DIY pixel sampling (~80 lines), 10×10 downsample, HSB bucketing, cached by `albumId` |
| 23 | Gradient rendering | Top-to-bottom `LinearGradient`, dominant color at 70% → darkened at 90%, `.colorScheme` override based on luminance |
| 24 | Track change gradient transition | Animated ease-in-out (~0.6s), pre-extract during gapless preload window |
| 25 | Player navigation | All navigation dismisses the player first, then navigates in the app's root context — no in-player browsing |
| 26 | Navigation architecture | Controlled `NavigationStack(path:)` per tab, `selectedTab` + `navigationPaths` on `AppState` |
| 27 | Play context tracking | `PlayContext` struct on `PlayQueue` — title, type, id — set when playback starts, not overwritten on queue modifications |
| 28 | Action feedback | Toast/snackbar: capsule with icon + text, 2s auto-dismiss, success haptic on iOS, driven by `AppState.showToast()` |
| 29 | Audio session — video conflict | `VideoPlaybackManager` pauses `AudioPlaybackManager` before starting; no auto-resume when video dismissed |
| 30 | Queue end behavior | Stop playback (no autoplay). Autoplay similar tracks deferred to v2. |
| 31 | Genre detail scope | Albums only for v1 — no songs section, no artists section within genre detail |
| 32 | Sort/filter persistence | No persistence across launches — reset to defaults each session |
| 33 | Download scope — new surfaces | Playlists and individual tracks downloadable; artists, genres, and songs list not downloadable |
| 34 | Download deduplication | Files stored once per `trackId`; don't delete file if another `DownloadItem` still references same `trackId` |
| 35 | Keyboard shortcuts | Not included in this feature — separate concern |
| 36 | Now Playing bar progress | 2pt `Rectangle` along top edge, accent-colored, proportional to `currentTime / duration`, non-interactive |
| 37 | Instant Mix (radio) | Context menu action on tracks, albums, artists — fetches up to 50 tracks via `/Items/{id}/InstantMix`, replaces queue |
| 38 | Instant Mix — no auto-refill | Queue stops when radio mix ends — no automatic refilling for v1 |
| 39 | Instant Mix — no dedicated UI | Purely a context menu action, no Radio tab or saved stations |

---

## Implementation Order

1. **Model changes** — extend `Track`, `Album`, `Artist`, `Playlist` with new fields; add `SortField.playCount`, `SleepTimerMode`, `PlayerPage`, `PlayContext`, `PlayContextType`
2. **Navigation architecture** — promote `selectedTab` and `navigationPaths` to `AppState`, convert all tabs to controlled `NavigationStack(path:)`, add `ToastView` overlay
3. **API layer** — add lyrics, favorites, playlist CRUD endpoints to `JellyfinAPIClient` + `JellyfinServerProvider` + mapper
4. **Music library navigation** — `SongListView`, `GenreListView`, `GenreDetailView`, expand `MusicLibraryView` picker, add discovery shelves
5. **Sorting & filtering** — sort menus, filter chips, downloaded-only toggle
6. **Playlist management** — `PlaylistDetailView`, `PlaylistPickerSheet`, wire up `PlaylistListView` navigation + CRUD
7. **Context menus** — build shared modifiers, apply across all music views, wire up toast feedback
8. **Full-screen player** — paged `AudioPlayerView` rewrite, `PlayerControlsView` extraction, `DominantColorExtractor`, gradient rendering
9. **Lyrics** — `LyricsView` with synced scrolling, implement `JellyfinServerProvider.lyrics()`, tap-to-seek
10. **Queue inline** — move `QueueView` into player page 3, add "Playing From" with `PlayContext`, "Clear Up Next", remove permanent edit mode
11. **Playback features** — sleep timer, audio quality badge, favorite button in player, video-pauses-audio
12. **Now Playing bar** — progress indicator, next track button
13. **Download extensions** — playlist downloads, single track downloads, deduplication check on deletion
14. **Instant Mix** — add `/Items/{id}/InstantMix` endpoint, wire "Start Radio" into context menus