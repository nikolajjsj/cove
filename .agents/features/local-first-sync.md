# Local-first sync

**Status:** specified, not started. Every load-bearing claim below was checked against the
Jellyfin 12.0 demo server or this tree; the *Verified* section at the end separates what
was tested from what was assumed.
**Not before 1.0 ships.**

---

## 1. The idea

Views stop calling `MediaServerProvider` and read local SQLite. The network becomes a sync
process that fills the database, not a request path the UI waits on. There is one source
of truth on the device and the server is where it comes from.

## 2. What it buys, ranked by worth

1. **Deletes the offline/online fork.** `OfflineMetadataRepository` exists only to shadow
   metadata for downloaded items, so every view that can show one branches on its source.
   One source removes that branch everywhere at once.
2. **Reactivity for free.** GRDB `ValueObservation` is already used by the download engine;
   views that observe the database update together without notification plumbing.
3. **Browse and search work offline and feel instant.**
4. **A second backend needs zero UI work.** An argument about UI coupling, not backends:
   `MediaServerKit` already abstracts the server and the mapping work is identical either
   way. Views simply never learn a second backend exists.

## 3. Non-goals

- **Offline artwork prefetch.** Images dominate "works offline" bytes and the database does
  not help. §9.3 defines the hook; the policy is separate work.
- **Replacing `MediaServerKit`.** The provider becomes the sync engine's input.
- **Music.** `FeatureFlags.musicEnabled` is false. Nothing music-typed is synced.
- **Being a general Jellyfin mirror.** We store what the UI reads. Nothing else.

## 4. Scope and seams

55 files under `Cove/Views` and `Cove/Components` mention a provider; **22 call a fetch
method**. The other 23 use `provider.imageURL`, a pure URL builder — no change.

```bash
grep -rl "provider\.\(items\|pagedItems\|item(\|search\|similarItems\|personItems\|libraries\)" Cove/Views Cove/Components | wc -l
```

`PagedCollectionLoader` takes a `PageFetcher` closure — `(limit, startIndex) async throws
-> Page` — and six views funnel through it. Swap the closure and those six change by one
line each.

The write path is `Cove/UserDataStore.swift`: optimistic update → server call → **rollback
on failure**. That rollback is what the outbox replaces (§6).

---

## 5. Data model

Additive migration `004_catalog`. `DatabasePool` (WAL) is already in use for file-backed
databases; keep it.

### 5.1 Keys

Every table is keyed by **`(serverId, userId, itemId)`**, not `(serverId, itemId)`.
Catalogue *visibility* is per user — library access and parental controls filter what
`/Items` returns — so two users on one server see two different catalogues. `ServerRecord`
already carries `userId`. Retrofitting a key is the most miserable migration there is;
get it right once.

### 5.2 Two tiers

**Catalogue tier** — everything grids, rails, filters and search need. Synced for the
whole library. Lean on purpose: measured ~3.2 KB/item with the fields Cove requests today
versus a few hundred bytes lean — roughly 64 MB against 8 MB for 20k items.

**Detail tier** — overview, people, media streams, chapters, trailers, provider ids.
Fetched lazily on first view, cached, pinned for downloads. Reuses `OfflineMetadataRecord`,
which is already `(itemId, serverId, mediaType, metadataJSON, updatedAt)`.

### 5.3 Tables

```
catalogItem
  serverId TEXT, userId TEXT, itemId TEXT           PK (serverId, userId, itemId)
  libraryId TEXT NOT NULL                            the top-level view it belongs to
  parentId TEXT, seriesId TEXT, seasonId TEXT        hierarchy
  type TEXT NOT NULL                                 Movie | Series | Season | Episode | BoxSet
  name TEXT NOT NULL, sortName TEXT NOT NULL         sortName from server; not in MediaItem today — add it
  productionYear INT, premiereDate REAL, dateCreated REAL NOT NULL
  runTimeTicks INT, communityRating REAL, criticRating REAL, officialRating TEXT
  indexNumber INT, parentIndexNumber INT
  seriesName TEXT
  imageTags TEXT                                     JSON {type: tag}; the tag is what busts Nuke's cache (§9.3)
  lastSeenInReconcile REAL NOT NULL                  set by reconcile; rows it did not see are the phantoms

catalogUserData
  serverId, userId, itemId                           PK, FK → catalogItem ON DELETE CASCADE
  played BOOL, playCount INT, isFavorite BOOL
  playbackPositionTicks INT, lastPlayedDate REAL
  Separate table on purpose: its own cursor, a far higher change rate, and writing it
  must not rewrite catalogue rows and wake every observation in the app.

catalogItemGenre   (serverId, userId, itemId, genreId, genreName)   genre is a grid filter today
catalogItemStudio  (serverId, userId, itemId, studioName)           studio is a grid filter today
  People are detail tier — nothing filters on them.

catalogItemSearch  FTS5 external-content table over catalogItem(name, sortName, seriesName)
  tokenize = 'unicode61 remove_diacritics 2'
  Maintained by triggers on catalogItem, so it cannot drift.

syncState
  serverId, userId, scope TEXT                       PK; scope ∈ {catalog, userData, reconcile, bootstrap}
  cursor REAL                                        server time, from the Date header (§6.4)
  bootstrapNextIndex INT, bootstrapComplete BOOL
  lastRunAt REAL, lastError TEXT

userDataOutbox                                      §7
  id TEXT PK, serverId, userId, itemId
  field TEXT                                         played | favorite | position
  value TEXT                                         JSON
  occurredAt REAL                                    device wall clock at the tap
  attempts INT, lastAttemptAt REAL, lastError TEXT

offline_metadata                                    existing; add:
  pinned BOOL NOT NULL DEFAULT 0                     set while a download exists (§9.1)
  lastAccessedAt REAL                                for eviction (§9.4)
```

### 5.4 Indexes

Driven by what `SortField` and `FilterOptions` actually contain, not speculation:

```
catalogItem (serverId, userId, libraryId, type, sortName)       default grid
catalogItem (serverId, userId, libraryId, type, dateCreated)    dateAdded / dateCreated
catalogItem (serverId, userId, libraryId, type, premiereDate)
catalogItem (serverId, userId, libraryId, type, communityRating)
catalogItem (serverId, userId, libraryId, type, criticRating)
catalogItem (serverId, userId, libraryId, type, runTimeTicks)
catalogItem (serverId, userId, libraryId, type, productionYear) decade filter
catalogItem (serverId, userId, seriesId, parentIndexNumber, indexNumber)   season/episode lists, NextUp
catalogItem (serverId, userId, lastSeenInReconcile)             phantom sweep
catalogUserData (serverId, userId, lastPlayedDate)              Resume, datePlayed sort
catalogUserData (serverId, userId, isFavorite), (serverId, userId, played)
catalogItemGenre (serverId, userId, genreId, itemId)
```

`SortField.random` is `ORDER BY random()` — fine locally. `playCount` and `datePlayed`
join `catalogUserData`.

### 5.5 Writes

Every page lands in **one transaction** via `INSERT … ON CONFLICT DO UPDATE`. Never
delete-and-reinsert: it fires every observation and loses `lastSeenInReconcile`.
`catalogUserData` is upserted from the same page (the DTO carries `UserData`), but only
for rows with no pending outbox entry — see §7.5.

---

## 6. The sync engine

### 6.1 Shape

One `actor CatalogSyncEngine` per signed-in server. It owns the three passes, serialises
them (never two passes concurrently — reconcile racing bootstrap would sweep rows bootstrap
has not reached), and exposes an `AsyncStream<SyncStatus>` for the UI.

Pure logic — page merging, cursor arithmetic, conflict rules, NextUp derivation — lives in
`CoveKit` as functions over values, tested without a network. The actor is thin.

### 6.2 Bootstrap

First connection, or after a full reset.

- **Per library**, not one global sweep: progress is meaningful, and a library can be
  excluded (§14).
- `GET /Items?parentId=<library>&recursive=true&fields=<catalogue set>&sortBy=DateCreated&sortOrder=Ascending&startIndex=N&limit=200`
- **Ascending `DateCreated`** so additions land past the cursor rather than shifting the
  unread tail. `sortBy` has **no unique key** — nothing in its enum is guaranteed distinct
  — so this paging is best-effort; §6.5 is what makes it safe.
- **Resumable:** `bootstrapNextIndex` is written in the same transaction as each page. Kill
  the app mid-bootstrap, relaunch, and it continues from the last committed page.
- **Non-blocking:** the UI reads whatever has landed. The grid shows a "Syncing… 4,200 of
  18,000" affordance, not a spinner. First run is the run everybody sees.
- On completion: set `bootstrapComplete`, set the `catalog` and `userData` cursors to the
  **`Date` header of the first bootstrap request**, then run one reconcile (§6.5) to
  backfill anything the offset walk skipped.

`includeItemTypes=Movie,Series,Season,Episode,BoxSet`. `recursive=true` returns
`Folder`, `Playlist`, and music types too; filter server-side, not after download.

### 6.3 Delta — catalogue axis only

```
catalogue:  GET /Items?recursive=true&fields=<catalogue set>&minDateLastSaved=<cursor − overlap>
```

Paged like bootstrap. A delta that returns more than ~5,000 rows is treated as a bootstrap.

**There is no user-data delta axis.** The spec originally paired `minDateLastSaved` with
`minDateLastSavedForUser`. Phase 0 disproved the second: on the 12.0 demo server a
favourite toggle, a mark-played, and a position write via `POST /UserItems/{id}/UserData`
were each followed by a `minDateLastSavedForUser` query cursored from the `Date` header
taken seconds earlier — and **all three returned 0 rows**, with and without an explicit
`userId`. The parameter filters on *something* (epoch → all, future → none) but not on
user-data writes. User data is synced by sweeps instead — §6.3a.

### 6.3a User-data sweeps

The UI needs three things fresh: what is in progress, what is a favourite, and what was
recently watched. Each is a small, indexed server query, verified to reflect a write
immediately:

| Sweep | Query | Local effect |
|---|---|---|
| In progress | `GET /UserItems/Resume?limit=100&fields=&enableImages=false` | Upsert positions. Any local row with `position > 0 AND played = 0` **not** in the response has finished or been reset elsewhere → refetch those ids (`GET /Items?ids=…`) and upsert |
| Favourites | `GET /Items?recursive=true&isFavorite=true&fields=&enableImages=false` | Set `isFavorite` on returned ids; clear it on local favourites not returned |
| Recently played | `GET /Items?recursive=true&isPlayed=true&sortBy=DatePlayed&sortOrder=Descending&limit=200&fields=&enableImages=false` | Upsert `played`, `playCount`, `lastPlayedDate` |
| Full | `GET /Items?recursive=true&includeItemTypes=<catalogue types>&fields=&enableImages=false` per library, paged — **782 bytes/item** with `UserData` (~15 MB for 20k) | Upsert every row's user data. Catches un-watch events and anything the hot sweeps miss |

The three hot sweeps run on every foreground and after playback; the full sweep runs daily
and on pull-to-refresh. A bare mark-played from another client that does not set
`DatePlayed` is invisible to the hot sweeps and lands with the daily full sweep — accepted.

**The outbox flushes before any sweep**, or a sweep pulls the server's stale value over
what the user just changed (§7.5).

### 6.4 Cursors — the part that is easy to get silently wrong

**There is no per-item timestamp to use.** `DateLastSaved` is in the `ItemFields` enum, so
you can *request* it, but it **never appears in the response** — tested. `UserData` carries
only `LastPlayedDate`, which does not move on a favourite toggle.

So the catalogue cursor is **server time at the moment of the request**, taken from the HTTP
`Date` response header of the *first page* of the pass. (User data has no cursor — §6.3a.) Never the device clock: a phone five
minutes fast never sees five minutes of changes, forever.

- Read `Date` from the first page's response. Record it as `candidateCursor`.
- Run every page. Commit each in its own transaction.
- Only after the **last page commits**, write `cursor = candidateCursor`. A pass that fails
  on page 7 of 9 leaves the cursor where it was and re-runs from there. Upserts make the
  repeat harmless.
- Query with `cursor − 120s`. `Date` has one-second precision and the server's clock is
  read after the query was planned; a two-minute overlap costs a handful of duplicate
  upserts and buys immunity to both.

### 6.5 Reconcile — bidirectional

Deltas **never report deletions**; there is no tombstones endpoint. And offset paging
under a moving list can **skip** rows. Both are the same pass:

```
per library:
  GET /Items?parentId=<library>&recursive=true&fields=&enableImages=false&enableUserData=false
      &includeItemTypes=<catalogue types>&startIndex=N&limit=500
  → the cheapest projection there is: 481 bytes/item measured (~15% of a fielded fetch,
    ~9.6 MB for 20k items). There is no true ids-only projection; this still carries
    blur hashes and aspect ratios.

  serverIds  = every id returned
  localIds   = SELECT itemId FROM catalogItem WHERE libraryId = ?

  missing    = serverIds − localIds   → fetch with the catalogue field set, upsert  (the skips)
  phantoms   = localIds − serverIds   → DELETE                                       (the deletions)
  UPDATE catalogItem SET lastSeenInReconcile = now WHERE itemId IN serverIds
```

Deleting a phantom **cascades** to `catalogUserData`, genre, studio, and search rows. It
does **not** touch `offline_metadata` where `pinned = 1` or the download itself — §9.2.

A library that has vanished from `/UserViews` is a phantom at the library level: delete
its rows, but only after `/UserViews` has returned successfully (an empty list on a 5xx
is not "no libraries").

### 6.6 Triggers and cadence

| Trigger | Runs |
|---|---|
| App foregrounded | outbox flush, then the three hot user-data sweeps; catalogue delta if > 15 min since last |
| Playback stopped | outbox flush, then Resume + recently-played sweeps (keeps Continue Watching and NextUp honest) |
| Pull-to-refresh | catalogue delta + full user-data sweep + reconcile for that library |
| Daily, opportunistic (`BGAppRefreshTask`) | full reconcile |
| Connectivity regained | flush outbox first (§7), *then* the hot sweeps |
| Sign-in | bootstrap |

The **outbox flushes before any user-data sweep**, always. Otherwise the sweep pulls the
server's stale value for something the user just changed and overwrites the local intent.

### 6.7 Failure taxonomy

Every pass classifies its error and behaves differently:

| Class | Examples | Behaviour |
|---|---|---|
| Transient | timeout, offline, 5xx, 429 | Keep cursor. Exponential backoff 30s → 16 min, jittered. Reset on success |
| Auth | 401 | Stop. Do not retry. Surface "sign in again". Cursors untouched |
| Permanent, item-level | 404 on a specific item fetch | Drop that item; continue the pass |
| Permanent, pass-level | 400 (we sent something malformed) | Stop, log at error, do not advance. This is a bug, not weather |
| Partial page | a page fails mid-pass | Pages already committed stay; cursor does not advance; retry as transient |

A pass never advances a cursor past data it did not commit. That single rule is most of
the correctness.

### 6.8 Cancellation

Sign-out, server switch, and app termination cancel the running pass. Because every page is
its own transaction and the cursor advances only at the end, cancellation at any point
leaves the database consistent and the next run resumes correctly.

---

## 7. Writes and conflict resolution

### 7.1 What can be edited offline

Three fields, because that is what the UI exposes: **played**, **favourite**, **playback
position**. (Playlists are music; off.)

### 7.2 The outbox replaces the rollback

`UserDataStore.toggleFavorite` today: optimistic → `POST` → **rollback on failure**. Offline,
every tap reverts. Under this design a tap **always succeeds locally**:

```
1. write catalogUserData                 (the UI updates through its observation)
2. append userDataOutbox row             (same transaction as 1)
3. if online, flush immediately
```

`UserDataStore` keeps its API and loses its rollback. Its `rebase()` — "merge server data
without clobbering in-flight optimistic values" — becomes the rule in §7.5, applied at the
database layer rather than in memory.

### 7.3 Coalescing

The outbox holds **at most one row per `(itemId, field)`**. A new write for the same pair
replaces the old row. Toggle a favourite six times offline and the server hears about it
once, with the final state. Positions: only the latest matters.

### 7.4 Replay — one call per row, idempotent

| Field | Endpoint | Notes |
|---|---|---|
| played = true | `POST /UserPlayedItems/{id}?datePlayed=<occurredAt>` | **`datePlayed` accepted** — the server records *when* you watched it, not when the phone reconnected |
| played = false | `DELETE /UserPlayedItems/{id}` | |
| favourite | `POST` / `DELETE /UserFavoriteItems/{id}` | |
| position | `POST /UserItems/{id}/UserData` with `{PlaybackPositionTicks, LastPlayedDate: occurredAt}` | Whole-object endpoint; carries the timestamp. Also `Played` if the position crossed the completion threshold |

All idempotent: replaying a row twice is harmless. Replay is **in `occurredAt` order**
across items so a watch-then-unfavourite sequence lands in the order it happened.

`OfflinePlaybackReportRepository` is folded into this outbox. Its `Progress`/`Stopped`
session reports need a live `PlaySessionId` the server no longer knows; the `UserData`
endpoint is what an offline report should have been calling all along.

### 7.5 Which edit wins

The rule, precisely:

> **The server is the truth for any field with no pending outbox row.
> A pending outbox row is the truth for its field until the server has acknowledged it.**

Consequences, worked through:

- **You mark a film watched on the phone offline; someone marks it unwatched on the TV.**
  You reconnect. Flush runs first: `POST /UserPlayedItems` — your edit lands, later in
  wall-clock, and the server now says *played*. Then the sweep pulls *played*. Consistent.
  The TV user sees it flip; that is correct — the phone's edit was made later.
- **Same, but the TV edit happened *after* your offline edit in real time.** Your
  `datePlayed` is earlier, but Jellyfin's played flag has no timestamp semantics — last
  writer wins on the server. Your flush overwrites the TV's later edit. **This is a real
  and accepted loss**: the alternative (compare `occurredAt` against a server timestamp
  that does not exist for `Played`) is not available. It is rare, it is the same behaviour
  every other Jellyfin client has, and it is documented here so nobody rediscovers it as
  a bug.
- **Position: you watch to 40 min offline; the TV watched to 60 min meanwhile.** Both are
  real. Rule: **the greater position wins unless the item was marked played** — you cannot
  un-watch by watching less. Applied at flush: read the server's current position first;
  if it is greater, drop the outbox row rather than replay it. This is the one field with
  a merge rather than a last-writer rule, because it is the one field where "later" and
  "further" are different things.
- **A sweep arrives while a row is pending.** The incoming `UserData` for that `(itemId,
  field)` is **ignored**; other fields on the same row are applied. This is `rebase()`,
  in SQL.
- **The item was deleted server-side while an edit was pending.** Replay returns 404.
  Classified permanent-item: drop the row, log at info. Never retry a 404.
- **Server unreachable.** Transient: row stays, `attempts++`, backoff. The existing
  `OfflineSyncManager` bails after three consecutive failures and has **no permanent-failure
  path** — a 404 blocks everything behind it forever. The new outbox must not inherit that:
  permanent failures are removed, transient ones are retried, and the queue is never
  blocked by a row that cannot succeed.
- **Sign-out with a non-empty outbox.** Ask. "You have 3 changes that haven't reached your
  server — sign out anyway?" Discarding intent silently is the one thing this design
  exists to prevent.

### 7.6 The completion threshold

Marking played at 90% is a Jellyfin *server* behaviour in progress reporting. Offline, the
phone has to apply it itself, using the same threshold the server would (from
`/System/Configuration`'s `MaxResumePct`, cached at sign-in; default 90). Otherwise a film
finished on a plane shows as unfinished until the next delta.

---

## 8. Derived feeds

`Continue Watching` and `Next Up` are **server-computed** today (`/UserItems/Resume`,
`/Shows/NextUp`). Derive both locally, **always**, not only offline: if Home changes shape
when connectivity changes, it reads as broken.

**Resume:**
```sql
SELECT … FROM catalogItem c JOIN catalogUserData u USING (serverId, userId, itemId)
WHERE u.playbackPositionTicks > 0 AND u.played = 0 AND c.type IN ('Movie','Episode')
ORDER BY u.lastPlayedDate DESC LIMIT 20
```

**Next Up**, per series with at least one played episode: the first episode by
`(parentIndexNumber, indexNumber)` that is unplayed *and* comes after the latest played
one. Specials (`parentIndexNumber = 0`) excluded. Series ordered by the latest
`lastPlayedDate` among its episodes.

Known divergence from the server: Jellyfin's NextUp honours `AiredEpisodeOrder` and a
"rewatching" mode. Neither is worth a network dependency on the Home screen. Documented;
not a bug.

---

## 9. Media management

### 9.1 Downloads pin detail rows

When a download is created, `offline_metadata.pinned = 1` for that item, and the detail
tier is fetched *now* if absent — a download without its metadata is a filename. When the
last download for an item is removed, `pinned = 0`. Eviction (§9.4) never touches a pinned
row. This is the entire remaining job of "offline metadata": pinning, not a parallel path.

### 9.2 Orphaned downloads

Reconcile deletes a catalogue row the server no longer lists. If a download exists for
it, the **download and its pinned detail row survive** — the user has the file and paid
for the bytes. The Downloads screen shows it with a "no longer on your server" badge and
it remains playable from disk. It disappears when the user deletes the download. Never
delete a user's file because the server forgot about it.

### 9.3 Artwork

Nuke's `DataCache` (500 MB) is keyed by URL, and image URLs embed the image **tag**. So the
catalogue syncing `imageTags` is what keeps artwork fresh: a replaced poster changes the
tag, the URL, and therefore the cache key. Nothing else needs to invalidate anything.

Prefetch hook, policy deferred: after bootstrap completes, optionally enqueue `Primary` at
grid size for every catalogue row via Nuke's prefetcher, Wi-Fi only. That is "offline
artwork", it is the expensive part, and it is a separate decision.

### 9.4 Storage budget

| Store | Bound | Eviction |
|---|---|---|
| `catalogItem` + friends | whole library, lean | Reconcile only. This *is* the app |
| `offline_metadata` | 200 MB soft cap | LRU by `lastAccessedAt`, **never `pinned`** |
| Nuke `DataCache` | 500 MB, existing | Nuke's own LRU |
| Downloads | user-controlled, existing | Never automatic |

Settings → Storage shows all four with real numbers, and "Clear cached details" evicts
unpinned `offline_metadata` only.

### 9.5 Play time still hits the server (when online)

`MediaSources`, transcoding URLs and `PlaySessionId` are session-scoped and go stale. At
play time online, fetch `/Items/{id}/PlaybackInfo` fresh — exactly as today. Offline, play
the local file. The **resume position** comes from `catalogUserData` in both cases: one
source, and it is the reason a film paused on the plane resumes correctly at home.

### 9.6 Sign-out and server switch

**Today** `AuthManager.disconnect()` deletes the `servers` row, and every catalogue table
cascades from it — so sign-out wipes the catalogue (and, pre-existing, the download
rows). That is a product decision to revisit, not something Phase 1 changed.

**Intended:** sign-out keeps the catalogue for that `(serverId, userId)` unless the user
chooses "Sign out and remove data" — re-login to the same account is then instant rather
than a bootstrap. Switching to a different `(serverId, userId)` simply changes which rows
are queried; nothing is deleted.

**Connection ids are now stable across re-sign-in.** Before Phase 1, every `connect()`
minted a fresh `UUID` and stored the token, downloads and (now) the catalogue under it;
signing in again to the same account orphaned all three. Found the first time the
screenshot driver signed in while session restore was still running: two `servers` rows,
two full bootstraps, 38 rows where there should be 19. `connect(url:credentials:reusing:)`
now keeps the saved id for a matching `(url, userId)`.

---

## 10. Observability

- `syncState.lastRunAt` / `lastError` per scope, surfaced in Settings → Server: "Library
  synced 4 min ago · 3 changes waiting to upload".
- The grid's empty state distinguishes *"nothing here"* from *"syncing — 4,200 of
  18,000"* from *"couldn't reach your server, showing what we have"*. Three states, three
  strings.
- `Logger` category `Sync`, one line per pass with counts. Never per row.

---

## 11. Staging

Each phase ends shippable. Gate before advancing.

| Phase | Work | Gate |
|---|---|---|
| 0 | **Done.** Read/write tests against the demo server | Passed: `Date` header present; reconcile primitives work; all four user-data sweep primitives reflect a write immediately. **Failed: `minDateLastSavedForUser`** — does not track user-data writes; replaced by §6.3a. Unverifiable without admin: whether `minDateLastSaved` bumps on metadata edits |
| 1 | **Done.** Migration 004, `CatalogSyncEngine`, `CatalogRepository`, `LibraryGridView` reads local once a library has bootstrapped or holds rows | Passed: bootstrap against the demo server landed exactly the server's type census (11 Movie, 1 Series, 1 Season, 6 Episode) with cursors in server time; a warm relaunch ran a delta and advanced them; 20 unit tests green and four guards mutation-tested. **Not yet:** *airplane mode* — `AppState.loadLibraries()` still comes from the network and empties `libraries` on failure, so with no connection there is no library to open. The library list must be persisted locally before the offline gate can pass; moved to Phase 2 |
| 2 | Remaining five `PagedCollectionLoader` views; Home rails including locally derived Resume / NextUp; Search over FTS5 | Search and Home work in airplane mode; Home does not change shape when connectivity toggles |
| 3 | Detail tier: lazy fetch, `pinned`, eviction; fold `OfflineMetadataRepository`; orphaned-download badge | The offline/online branch is **deleted**, not bypassed. Delete a downloaded item server-side: it stays playable with the badge |
| 4 | Outbox: replace `UserDataStore` rollback, coalescing, ordered replay, position merge, 404 dropping; fold `OfflinePlaybackReportRepository` | Toggle favourite six times offline → one request. Watch to 40 min offline while the server is at 60 → phone yields. Item deleted server-side with a pending edit → row dropped, queue continues |
| 5 | Retire remaining provider fetch calls; sync status UI; `BGAppRefreshTask` | Nothing in `Cove/Views` calls a provider fetch method. Grep returns 0 |

Phase 0 is a day and is the only phase that can invalidate the rest. Throw its code away.

---

## 12. Verification

**Mutation-test every guard.** A test that passes with the logic disabled is worthless, and
sync tests are unusually easy to write that way:

| Guard | Mutation | Must fail with |
|---|---|---|
| Reconcile removes phantoms | skip the DELETE | phantom row persists |
| Reconcile backfills skips | skip the missing-fetch | row stays absent |
| Cursor advances only after last page | advance on page 1 | edit between page 1 and N is lost |
| Cursor from `Date` header | use `Date()` | with clock set 5 min fast, edit is never seen |
| Resume sweep detects items that left the set | skip the refetch | a film finished on the TV stays in Continue Watching |
| Favourites sweep clears stale | skip the clear | an unfavourited item stays a favourite |
| Outbox coalescing | append instead of replace | six rows, six requests |
| Pending row beats delta | apply delta unconditionally | local favourite reverts |
| Position merge | always replay | 40 min overwrites 60 |
| 404 is permanent | classify as transient | queue blocks |
| Pinned rows survive eviction | ignore `pinned` | downloaded item loses metadata |

Sync logic is pure functions in `CoveKit` — `merge(page:into:)`, `reconcile(local:server:)`,
`nextUp(episodes:userData:)`, `resolve(outbox:incoming:)` — tested with values, no network,
same reasoning as the existing mapper tests. The actor is a thin loop around them.

End-to-end against the demo server is a real 12.0 target; see `AGENTS.md`.

---

## 13. Multi-server and multi-user

Every key includes `userId` (§5.1). Today there is **no UI to add or switch servers**, so
this path is untested end to end — but the schema must not make it impossible later. Nothing
in this design assumes one server or one user; it assumes one *active* `(serverId, userId)`
at a time, which is what `AppState` already models.

---

## 14. Open decisions — genuinely the owner's

1. **Very large libraries.** Above some size, bootstrap should either ask or be per-library
   opt-in. 50k items ≈ 20 MB lean and a few minutes; 500k is a different product. Pick a
   number before Phase 1.
2. **Local search semantics.** FTS5 with `unicode61 remove_diacritics 2` is instant and
   offline but does not fuzzy-match like the server. Recommended: accept it. It is a
   visible change and should be decided, not discovered.
3. **Privacy policy line.** A local catalogue of the whole library is new on-device data.
   `nikolajjsj.com/cove/privacy-policy` needs a sentence.
4. **The played-flag race** (§7.5, second bullet). Accepting last-writer-wins is
   recommended and is what every other client does; it is listed so it is a decision.

---

## 15. Verified

Against the 12.0 demo server and this tree — tested, not assumed:

- `minDateLastSaved` filters (future cutoff → 0, epoch → all). `minDateLastSavedForUser` also
  filters on *something* — but **not on user-data writes**: favourite, mark-played and a
  position `POST` were each invisible to it seconds later, with and without `userId`.
- `/UserItems/Resume`, `isFavorite=true`, `isPlayed=true&sortBy=DatePlayed`, and `ids=` all
  reflect a write immediately. Full user-data sweep is 782 bytes/item.
- `POST /UserItems/{id}/UserData` with `PlaybackPositionTicks`/`Played` works on 12.0 (200,
  state changed). `POST /UserPlayedItems` resets position to 0 as a side effect.
- `DateLastSaved` **does not appear in responses** even when requested via `fields`. `UserData` carries only `LastPlayedDate`.
- The server sends an HTTP `Date` header.
- `sortBy` has no `Id`; no option is unique.
- Cheapest reconcile projection: 481 bytes/item.
- `recursive=true` returns `Series`, `Season`, `Episode`, `Folder`, `Playlist` and music types in one feed; episodes carry `SeriesId`, `SeasonId`, `ParentIndexNumber`, `IndexNumber`.
- `GenreItems` come per item with ids; `/Genres` exists.
- `POST /UserPlayedItems/{id}` accepts `datePlayed`; `POST /UserItems/{id}/UserData` takes the whole `UpdateUserItemDataDto` including `LastPlayedDate`.
- `/UserItems/Resume` and `/Shows/NextUp` are the feeds Home uses today.
- FTS5 is compiled into GRDB here (`SQLITE_ENABLE_FTS5` in its `Package.swift`) and present in system SQLite.
- `DatabasePool` (WAL) is already used for file-backed databases.
- `ServerRecord` carries `userId`.
- `OfflineMetadataRecord` is `(itemId, serverId, mediaType, metadataJSON, updatedAt)`.
- `UserDataStore` is optimistic-with-rollback and has `rebase()`.
- `OfflineSyncManager` replays sequentially with no permanent-failure path.
- Fetch-call surface is 22 files; `PageFetcher` is `(limit, startIndex) async throws -> Page`.
- End to end on iPad Pro 13-inch against the demo server: `catalog_items` = 19, `catalog_user_data` = 19, `catalog_item_genres` = 37, FTS = 19; both libraries `bootstrapComplete`; cursors `15:28Z` while the host is on CEST.
- Every `connect()` created a new `servers` row (two rows, same url and user, 83 s apart) before the reuse fix.

**Not verified:**
- Whether `DateLastSaved` bumps on *every* kind of server-side metadata edit (it is
  invisible in responses, so this can only be tested behaviourally — Phase 0's third gate).
- Multi-user on one server, end to end. No UI exists to exercise it.
- `MaxResumePct` location in `/System/Configuration` on 12.0.
