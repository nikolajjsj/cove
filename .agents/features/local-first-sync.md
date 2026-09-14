# Local-first sync

**Status:** proposed, not started. Sized against a real 12.0 server; no code written.
**Not before 1.0 ships.** This touches the 47 files that currently call a provider directly.

## The idea

Views stop calling `MediaServerProvider` and read local SQLite instead. The network
becomes a sync process that fills the database, not a request path the UI waits on.

## What this actually buys

Ranked by how much they are worth, which is not the order they usually get argued in.

1. **It deletes the offline/online fork.** `OfflineMetadataRepository` exists only to
   shadow metadata for downloaded items, so every view that can show a downloaded item
   branches on which source it is reading. One source removes that branch everywhere at
   once. This is the biggest win and the least discussed.
2. **Reactivity for free.** GRDB `ValueObservation` is already used by the download
   engine. Once views observe the database, favouriting an item updates every screen
   showing it with no notification plumbing.
3. **Browse and search work offline and feel instant**, because they are local queries
   rather than paged HTTP.
4. **A second backend needs zero UI work.** Note this is an argument about *UI coupling*,
   not about backends: `MediaServerKit` already abstracts the server, and the per-backend
   mapping work is identical either way. What changes is that it moves provider→DB
   instead of provider→view, so views never learn a second backend exists.

## Non-goals

- **Offline artwork.** Images are the bulk of the bytes in "works offline" and the
  database does not help. Separate piece of work, separate decision.
- **Replacing `MediaServerKit`.** The provider protocol stays; it becomes the sync
  engine's input rather than the view layer's.
- **Music.** `FeatureFlags.musicEnabled` is false. Do not sync what is not shipped.

## What makes it possible, and the trap in it

`/Items` accepts `minDateLastSaved` and `minDateLastSavedForUser`. Both genuinely filter
— verified against the 12.0 demo server, not just read in the spec.

Two axes matter because they change at completely different rates: catalogue edits are
rare, user data (watched, resume, favourite) changes constantly and from other clients.

**Neither reports deletions, and there is no tombstones endpoint.** An item removed from
the server is simply never mentioned again. Deltas alone therefore drift into phantom
rows that fail at playback. See the bullet in `AGENTS.md`; the answer is a third pass,
below, and it has to be designed in from the start rather than bolted on.

## Schema

Additive migration (`004_catalog`). Everything keyed by `serverId` — multi-server is
already the existing convention and retrofitting it is miserable.

**`catalogItem`** — the lean index. Only what grids, rails and search need: ids, parent
and series ids, type, name, sort name, year, runtime, image tags, ratings, index numbers,
`dateLastSaved`. **No overview, no people, no media sources, no studios.**

That restraint is the whole storage argument. Measured on the demo server: ~3.2 KB/item
with the fields Cove currently requests, versus a few hundred bytes lean. For a
20k-item library that is ~64 MB against ~8 MB. Re-measure before committing to it:

```bash
curl -s "$SERVER/Items?recursive=true&limit=50&fields=Overview,Genres,People,ProviderIds,MediaSources,Studios" -H "$AUTH" | wc -c
```

**`catalogUserData`** — played, play count, favourite, position, last played,
`dateLastSavedForUser`. Deliberately a separate table, for three reasons: it has its own
delta cursor, it changes far more often, and writing it must not rewrite catalogue rows
and wake every `ValueObservation` in the app.

**`syncState`** — per `(serverId, scope)`: delta cursor, bootstrap cursor, bootstrap
complete flag, last reconcile time.

**`catalogItemSearch`** — FTS5 over name and sort name.

**Detail cache** — extend `OfflineMetadataRecord` rather than adding a table. Today it
holds rich metadata for downloaded items; it becomes a lazily-populated detail cache for
*any* item, and downloads simply pin their rows. That reframing is what collapses the
fork in point 1.

## The sync loop

Three passes, deliberately separate.

1. **Bootstrap** — first connection. Pages `/Items` with the lean field set, writing in
   batches. Must be *resumable* (persist the page cursor) and *non-blocking*: the UI
   reads whatever has landed while it continues. A blocking first sync on a large library
   is a terrible first run, and first run is the one everybody sees.
2. **Delta** — `minDateLastSaved` for the catalogue, `minDateLastSavedForUser` for user
   data, each against its own cursor. Cheap enough to run on foreground.
3. **Reconcile** — id-only fetch per library, diffed against local ids, removing what the
   server no longer lists. This is the only answer to deletions. Roughly a third the
   payload of a fielded fetch, so it is affordable on a schedule (daily, plus
   pull-to-refresh) rather than per launch.

**Cadence:** user data on foreground and after playback stops; catalogue on foreground,
throttled; reconcile daily and on explicit refresh.

## Writes

User actions must stay optimistic or the app feels worse than it does today. Write
locally, enqueue to the server, let the next user-data delta confirm. `OfflinePlaybackReportRepository`
already does exactly this for playback — generalise it into an outbox rather than
inventing a second mechanism.

Conflict rule: **server wins, except for local writes still in the outbox.** Without that
exception a delta arriving mid-flight silently reverts what the user just tapped.

## Staging

Each phase ends in a shippable state. Do not start the next until the gate passes.

| Phase | Work | Gate |
|---|---|---|
| 0 | Throwaway harness against a real server: delta both axes, reconcile, measure | Deletions are detected. If not, stop — the plan is wrong |
| 1 | Migration, sync engine, `LibraryGridView` reads local | Grid browses offline; paging instant; a server-side delete disappears within one reconcile |
| 2 | Home rails + Search over FTS5 | Search returns results in airplane mode |
| 3 | Detail views; fold `OfflineMetadataRepository` into the detail cache | The offline/online branch is deleted, not merely bypassed |
| 4 | Write outbox for favourite / watched / resume | Toggle offline, kill the app, relaunch online: it reaches the server |
| 5 | Retire remaining direct provider calls | Nothing in `Cove/Views` imports a provider |

Phase 0 is a day and is the only phase that can invalidate the rest. Do it first and
throw the code away.

## Verification

- Mutation-test the reconcile pass specifically: delete an item server-side, revert the
  reconcile fix, and confirm the phantom comes back. A reconcile test that passes with
  the logic disabled is worthless, and this one is easy to write that way by accident.
- Sync logic goes in `CoveKit` as pure functions over inputs, testable without a network
  — same reasoning as the existing mapper tests.
- The demo server is a real 12.0 target for end-to-end runs: see `AGENTS.md`.

## Open decisions

- **Very large libraries.** Is there a ceiling where bootstrap is refused, or is sync
  per-library opt-in? Needs a number before phase 1.
- **Local search will not match server search.** Jellyfin normalises and fuzzy-matches;
  FTS5 does not, out of the box. Instant and offline is probably the better trade, but it
  is a visible behaviour change and should be a decision, not a surprise.
- **Storage disclosure.** A local catalogue of a whole library is new on-device data and
  the privacy policy at `nikolajjsj.com/cove/privacy-policy` will need a line.
