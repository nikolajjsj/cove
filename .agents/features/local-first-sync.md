# Local-first sync

**Status:** proposed, not started. Assumptions verified against a real 12.0 server and
against this codebase — see *Verified* at the end for what was actually checked and what
was not.
**Not before 1.0 ships.**

## The idea

Views stop calling `MediaServerProvider` and read local SQLite instead. The network
becomes a sync process that fills the database, not a request path the UI waits on.

## What this actually buys

Ranked by worth, which is not the order they usually get argued in.

1. **It deletes the offline/online fork.** `OfflineMetadataRepository` exists only to
   shadow metadata for downloaded items, so every view that can show a downloaded item
   branches on which source it is reading. One source removes that branch everywhere at
   once. Biggest win, least discussed.
2. **Reactivity for free.** GRDB `ValueObservation` is already used by the download
   engine. Once views observe the database, favouriting an item updates every screen
   showing it with no notification plumbing.
3. **Browse and search work offline and feel instant** — local queries, not paged HTTP.
4. **A second backend needs zero UI work.** This is an argument about *UI coupling*, not
   about backends: `MediaServerKit` already abstracts the server and the per-backend
   mapping work is identical either way. What changes is that it moves provider→DB
   instead of provider→view, so views never learn a second backend exists.

## Non-goals

- **Offline artwork.** Images are the bulk of the bytes in "works offline" and the
  database does not help. Separate work, separate decision.
- **Replacing `MediaServerKit`.** The provider stays; it becomes the sync engine's input
  rather than the view layer's.
- **Music.** `FeatureFlags.musicEnabled` is false. Do not sync what is not shipped.

## Scope

Smaller than it looks. 55 files under `Cove/Views` and `Cove/Components` mention a
provider, but **only 22 call a fetch method**. The other 23 use `provider.imageURL`
only — a pure URL builder that makes no request and needs no change. Re-check before
planning work:

```bash
grep -rl "provider\.\(items\|pagedItems\|item(\|search\|similarItems\|personItems\|libraries\)" Cove/Views Cove/Components | wc -l
```

Better still, the paging seam is narrow. `PagedCollectionLoader` takes a `PageFetcher`
**closure**, and six views funnel through it (`LibraryGridView`, `PagedMediaGridView`,
`GenreDetailView`, `SongListView`, `VideoGenreDetailView`, `StudioDetailView`). Convert
the fetcher and those six change by one line each; the loader itself does not change.

## What makes it possible, and the two traps in it

`/Items` accepts `minDateLastSaved` and `minDateLastSavedForUser`. **Both verified to
genuinely filter** against the 12.0 demo server — future cutoff returns 0, epoch cutoff
returns everything. Two axes matter because catalogue edits are rare while user data
changes constantly and from other clients.

**Trap 1 — deltas never report deletions.** There is no tombstones endpoint. A removed
item is simply never mentioned again, so deltas alone drift into phantom rows that fail
at playback.

**Trap 2 — there is no stable unique sort key.** `sortBy` offers no `Id`; every option
(`DateCreated`, `SortName`, …) can tie. Bootstrap therefore pages by offset over a moving
list, and anything inserted or deleted mid-bootstrap shifts it. Deletions shift the tail
*backwards* and silently **skip** items — a missing row, which a deletion-only reconcile
would never repair.

Both traps have the same answer: **reconcile must be bidirectional** — remove local ids
the server no longer lists, *and* fetch ids the server lists that are missing locally.
One mechanism, both problems, and it makes bootstrap paging self-healing rather than
something that must be made perfect.

Page bootstrap by `DateCreated` **ascending** regardless, so newly added items append
past the cursor instead of shifting the unread tail.

## Schema

Additive migration `004_catalog` (001–003 exist). Everything keyed by `serverId`, the
existing convention.

**`catalogItem`** — the lean index. Only what grids, rails and search need: ids, parent
and series ids, type, name, sort name, year, runtime, image tags, ratings, index numbers,
`dateLastSaved`. **No overview, no people, no media sources, no studios.** That restraint
is the whole storage argument: ~3.2 KB/item with the fields Cove currently requests
versus a few hundred lean — roughly 64 MB against 8 MB for 20k items. Re-measure before
committing.

**`catalogUserData`** — played, play count, favourite, position, last played,
`dateLastSavedForUser`. Separate table on purpose: its own delta cursor, a far higher
change rate, and writing it must not rewrite catalogue rows and wake every
`ValueObservation` in the app.

**`syncState`** — per `(serverId, scope)`: delta cursor, bootstrap cursor, bootstrap
complete flag, last reconcile time.

**`catalogItemSearch`** — FTS5 over name and sort name. **Confirmed available**: GRDB's
`Package.swift` defines `SQLITE_ENABLE_FTS5` unconditionally, and system SQLite has the
module at runtime.

**Detail cache** — extend `OfflineMetadataRecord` rather than adding a table. It is
already `(itemId, serverId, mediaType, metadataJSON, updatedAt)` — a keyed detail cache
by shape. It becomes lazily populated for *any* item, which is what collapses the fork in
point 1. **It needs an explicit pin or eviction rule first:** downloads currently rely on
that row existing, so a general cache that evicts would quietly strip metadata from
downloaded items.

## The sync loop

1. **Bootstrap** — first connection. Pages `/Items` with the lean field set, `DateCreated`
   ascending, writing in batches. Must be *resumable* (persist the page cursor) and
   *non-blocking*: the UI reads whatever has landed. A blocking first sync on a large
   library is a terrible first run, and first run is the one everybody sees.
2. **Delta** — `minDateLastSaved` for the catalogue, `minDateLastSavedForUser` for user
   data, each against its own cursor. **Advance each cursor from the maximum timestamp in
   the server's own response, never from the device clock** — clock skew between phone
   and server silently drops changes that fall in the gap.
3. **Reconcile** — bidirectional, per library, as above. Cheapest projection is
   `enableImages=false&enableUserData=false&fields=`, measured at **481 bytes/item**
   (~15% of a fielded fetch, ~9.6 MB for 20k items). Note there is no true ids-only
   projection: that response still carries blur hashes and aspect ratios.

**Cadence:** user data on foreground and after playback stops; catalogue on foreground,
throttled; reconcile daily and on explicit refresh.

## Writes

User actions must stay optimistic or the app feels worse than today. Write locally,
enqueue, let the next user-data delta confirm. `OfflinePlaybackReportRepository` already
has exactly this shape — `save` / `fetchUnsent` / `markSynced` / `deleteOld` — so
generalise it rather than inventing a second mechanism.

Conflict rule: **server wins, except for local writes still in the outbox.** Without that
exception a delta arriving mid-flight silently reverts what the user just tapped.

## Staging

Each phase ends shippable. Do not start the next until the gate passes.

| Phase | Work | Gate |
|---|---|---|
| 0 | Throwaway harness: both deltas, bidirectional reconcile, measure | A server-side delete is removed **and** a deliberately skipped item is backfilled. If either fails, stop |
| 1 | Migration, sync engine, local `PageFetcher`; point `LibraryGridView` at it | Grid browses offline; paging instant; a server-side delete disappears within one reconcile |
| 2 | Remaining five `PagedCollectionLoader` views, Home rails, Search over FTS5 | Search returns results in airplane mode |
| 3 | Detail views; fold `OfflineMetadataRepository` into the pinned detail cache | The offline/online branch is deleted, not merely bypassed |
| 4 | Write outbox for favourite / watched / resume | Toggle offline, kill the app, relaunch online: it reaches the server |
| 5 | Retire the remaining direct provider calls | Nothing in `Cove/Views` calls a provider fetch method |

Phase 0 is a day and is the only phase that can invalidate the rest. Do it first and
throw the code away.

## Verification

- **Mutation-test the reconcile pass in both directions.** Delete an item server-side,
  revert the fix, confirm the phantom returns; then skip an item during bootstrap, revert
  the backfill, confirm it stays missing. A reconcile test that passes with the logic
  disabled is worthless and this one is easy to write that way by accident.
- Sync logic goes in `CoveKit` as pure functions over inputs, testable without a network
  — same reasoning as the existing mapper tests.
- The demo server is a real 12.0 target for end-to-end runs; see `AGENTS.md`.

## Open decisions

- **Very large libraries.** Is there a size where bootstrap is refused, or is sync
  per-library opt-in? Needs a number before phase 1.
- **Local search will not match server search.** Jellyfin normalises and fuzzy-matches;
  FTS5 does not out of the box. Instant and offline is probably the better trade, but it
  is a visible behaviour change and should be a decision, not a surprise.
- **Storage disclosure.** A local catalogue of a whole library is new on-device data and
  the privacy policy at `nikolajjsj.com/cove/privacy-policy` will need a line.

## Verified

Checked against the 12.0 demo server and this tree, not assumed:

- `minDateLastSaved` **and** `minDateLastSavedForUser` both filter correctly.
- No `Id` option in `sortBy` — hence trap 2.
- Cheapest reconcile projection is 481 bytes/item.
- FTS5 is compiled into GRDB here and present in system SQLite.
- `OfflineMetadataRecord` is already a keyed JSON detail cache.
- `OfflinePlaybackReportRepository` already has the outbox shape.
- Real fetch-call surface is 22 files, not 55.

**Not verified:** whether `DateLastSaved` reliably bumps on every kind of server-side
metadata edit, and whether multi-server keying works end to end — there is no UI to add
or switch servers today, so that path has never been exercised.
