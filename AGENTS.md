# Agent guide for Swift and SwiftUI

This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SwiftData, and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.


## Core instructions

- Target iOS 26.0 or later. (Yes, it definitely exists.)
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.


## Swift instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- The app and widget targets build with `-default-isolation=MainActor` and `InferIsolatedConformances`, so **everything in `Cove/` and `CoveWidget/` is implicitly `@MainActor`** — including plain structs, enums, and extensions that hold no state. Mark value types and pure-logic extensions `nonisolated` when anything off the main actor touches them: a `@Sendable` closure reading a computed property, or a `Codable` conformance a library requires to be nonisolated (`Defaults.Serializable` is the one that bites). The symptom is "cannot be referenced from a Sendable closure" or "conformance ... crosses into main actor-isolated code", and the fix is almost always `nonisolated` on the declaration rather than reshaping the call site. CoveKit has no default isolation, so this applies only to the two app targets.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.


## SwiftData instructions

If SwiftData is configured to use CloudKit:

- Never use `@Attribute(.unique)`.
- Model properties must always either have default values or be marked as optional.
- All relationships must be marked optional.


## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- If the project uses Localizable.xcstrings, prefer to add user-facing strings using symbol keys (e.g. helloWorld) in the string catalog with `extractionState` set to "manual", accessing them via generated symbols such as  `Text(.helloWorld)`. Offer to translate new keys into all languages supported by the project.


## App-specific patterns

- **User data (favorites, played state, play counts)** must always be read through `UserDataStore`, never directly from a model's `userData` property. `UserDataStore` holds live optimistic overrides that may differ from the stale server value stored on the model. Use `appState.userDataStore?.isFavorite(item.id, fallback: item.userData) ?? item.userData?.isFavorite ?? false` (or the equivalent `isPlayed` variant). Never write `item.userData?.isFavorite ?? false` at a call site.

- **Download storage sizes** must be measured from disk via `DownloadStorage` (`totalDiskUsage()`, `diskUsage(serverId:)`, `diskUsage(for:)`), never by summing `DownloadItem.totalBytes` / `downloadedBytes` from the database. Those DB fields start as the server's `MediaSource.size` estimate, which is the *original* file size even when the download goes through the transcode endpoint, and they exclude artwork and subtitle sidecars stored alongside the media file. They are only corrected to the real size at completion, so older records keep the stale estimate. Any UI showing "space used" must also agree on scope — the Settings row and `StorageManagementView` both report all servers.

- **`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are shared** by `AudioPlaybackManager` and `VideoPlaybackManager`, and neither owns them. Register command targets through `RemoteCommandRegistry` so teardown removes only your own — `removeTarget(nil)` removes *every* target on that command and silently kills the other player's lock-screen controls. Likewise, never assign `nowPlayingInfo = nil` unconditionally: stamp what you publish (video uses `MPNowPlayingInfoPropertyExternalContentIdentifier`) and clear it only if it is still yours. And configure the `AVAudioSession` category at init but only `setActive(true)` when playback actually starts — activating on construction interrupts whatever the user was already listening to.

- **Jellyfin server API compatibility.** The app targets Jellyfin **10.9 or later**; server 12.0 removed and disabled things earlier clients relied on. Two rules follow from that:

  - **Token auth in URLs uses `ApiKey`, never the legacy `api_key`.** 12.0 disables the legacy query parameter (and the `X-Emby-*` headers) unless the admin re-enables `EnableLegacyAuthorization`. Use `JellyfinAuthHeader.apiKeyQueryItem(token:)` for any URL handed to `AVPlayer` or a background download task; everything else authenticates with the `Authorization: MediaBrowser …` header. Download URLs are the exception to "put the token in the URL": `DownloadItem.remoteURL` is persisted, so it is stored **credential-free** (`DownloadManagerService.credentialFreeURL(from:)`) and the token is attached per request from `authTokenProvider`. Never persist a URL with a token in it — that writes a credential to the database in plaintext, and a stored token goes stale the moment the user signs in again.

  - **Never use a `/Users/{userId}/…` route.** They were deprecated in 10.9 and *deleted* in 12.0. The replacements take `userId` as a query parameter instead: `/Items`, `/Items/{itemId}`, `/UserItems/Resume`, `/UserViews`, `/Items/Suggestions`, `/UserFavoriteItems/{itemId}`, `/UserPlayedItems/{itemId}`, `/Items/{itemId}/SpecialFeatures`, `/Items/{itemId}/LocalTrailers`.

  Before adding or changing an endpoint, verify it against the real spec rather than from memory — it lists removals, deprecations, and the exact parameter names and casing:

  ```bash
  curl -sL https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json -o /tmp/jf.json && python3 -c "import json;s=json.load(open('/tmp/jf.json'));print(s['info']['version']);op=s['paths']['/Items']['get'];print(op.get('deprecated',False));print([q['name'] for q in op['parameters'] if q['in']=='query'])"
  ```

- **Never build a path or a URL directly from server-supplied data.** The media server chooses item ids, `TranscodingUrl`, trailer URLs, and subtitle language tags. Two Foundation APIs make this dangerous in ways that read as safe:

  - `URL.appending(path:)` is a *path* append, not a component append. It does not escape `/` and does not collapse `..`, and `FileManager` resolves both at syscall time. Anything server-supplied that becomes a path segment must go through `DownloadStorage.safeComponent(_:)` first — including the string-interpolated `relative*Path` helpers, which are persisted and must agree with the URL builders. Guard destructive or writing operations with `DownloadStorage.isContained(_:)`.
  - `URL(string:relativeTo:)` performs RFC 3986 resolution, which **discards the base entirely** when the reference carries its own scheme, and replaces the authority for a protocol-relative `//host`. Never resolve a server-supplied URL string against `baseURL`; take only its `path` and `query` via `URLComponents` and keep the scheme, host, and port from `baseURL`, as `hlsStreamURL` does.

  The same mistake appeared independently in three places, so treat it as a pattern this codebase attracts rather than a one-off. Regression tests live in `DownloadStoragePathTraversalTests` and the `hlsStreamURL` tests in `JellyfinAPITests`.

- **Testing the playback and download engines.** Both are covered by seams that already exist — `AudioPlayerBackend`/`NowPlayingProvider` for audio, `DownloadSession`/`DownloadTaskHandle` for transfers — plus `DatabaseManager()`'s in-memory initialiser and `DownloadStorage(rootDirectory:)`, so tests run the real code against real files and the real schema rather than mocks. Download rows need a `servers` row behind them; the foreign key is enforced.

  `VideoPlaybackManager` is the deliberate exception: it drives a real `AVPlayer`, which is cheap to construct and needs no window or network so long as nothing has to decode. Do not extract a protocol for it — that would mean wrapping `AVPlayerItem`, `AVMediaSelectionGroup`, and `CMTime` for no test benefit.

  Three traps, each of which has already produced a test that passed for the wrong reason:

  - `NotificationCenter.notifications(named:)` only starts receiving once its task body has run, so a notification posted too soon after `init` is silently missed. Settle *before* posting, not just after.
  - `Task.yield()` does not advance the clock. Anything waiting on real I/O — a file read, a URL load — needs an actual sleep or a polling loop with a deadline.
  - `AVPlayer` genuinely fails the dummy stream URLs these tests use, asynchronously and at unpredictable times. Never assert on a playback *error count*; assert on stop reports or specific item ids instead.

  When a test covers a bug fix, verify it fails with the fix reverted. Two of the tests here passed either way until that check was run.

- **Filter UI goes in the toolbar, not above the content.** Any view that filters a media list composes `MediaFilterSelection` (bundles the bindings, derives the active set) with `MediaFilterMenu` in a `.primaryAction` toolbar item and `ActiveFilterBar` above the content. The bar renders *only* applied filters and collapses to zero height when there are none — do not add a row of always-visible unselected chips, which is what this replaced. Add a new filter by extending `MediaFilterSelection`, so the menu and the bar pick it up together.

- **Never trigger a system permission prompt at launch.** Notifications, and anything else with an OS alert, are requested at the moment the feature is first used — see `DownloadNotificationPermission`, asked at the first download rather than in `CoveApp.init`. A prompt during onboarding asks the user to approve something they have no context for, and a denial there is effectively permanent.

- **The app icon is generated, not exported.** Change it by editing `Tools/GenerateAppIcon.swift` or `Cove/Components/Jellyfish/JellyfishGeometry.swift` and re-running the generator — never by editing the PNGs in `AppIcon.appiconset`, since the light, dark, tinted, and macOS images all come from one set of parameters and will drift apart if touched individually. The generator is *not* a `swift` script: it compiles the shared geometry alongside itself, and it has no top-level code, so it must be built with `swiftc`.

  `JellyfishGeometry` is the single source of truth for the creature's curves — the icon and the animated onboarding mark (`JellyfishMark`) both draw it, which is the only reason the home screen and the first screen agree. Edit it and you change both; that is intended, so check both before committing. It is laid out **y-down to match SwiftUI**, and the icon generator flips its context once before drawing. Anything drawn with CoreGraphics from it needs that flip.

  Re-running with no source change reproduces every installed PNG byte-for-byte, which is the check that the catalogue and the code are still in sync (the generator also writes `preview-*.png` for eyeballing, which are intentionally not installed — compare only `AppIcon-*`):

  ```bash
  mkdir -p /tmp/iconcheck && swiftc -O Tools/GenerateAppIcon.swift Cove/Components/Jellyfish/JellyfishGeometry.swift -o /tmp/genicon && /tmp/genicon /tmp/iconcheck && for f in /tmp/iconcheck/AppIcon-*.png; do cmp -s "$f" "Cove/Assets.xcassets/AppIcon.appiconset/$(basename "$f")" || echo "DIFF $(basename "$f")"; done; echo done
  ```

  `Contents.json` is maintained by hand, so adding a size means adding both an entry there and an output in the generator's emit loop. Verify a change actually reached the bundle rather than trusting a silent build — `actool` does not warn about a variant it never received:

  ```bash
  xcrun assetutil --info <DerivedData>/Build/Products/Debug-iphonesimulator/Cove.app/Assets.car | grep -i AppIcon
  ```

## PR instructions

- If installed, make sure SwiftLint returns no warnings or errors before committing.


## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:

- `DocumentationSearch` — verify API availability and correct usage before writing code
- `BuildProject` — build the project after making changes to confirm compilation succeeds
- `GetBuildLog` — inspect build errors and warnings
- `RenderPreview` — visually verify SwiftUI views using Xcode Previews
- `XcodeListNavigatorIssues` — check for issues visible in the Xcode Issue Navigator
- `ExecuteSnippet` — test a code snippet in the context of a source file
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` — prefer these over generic file tools when working with Xcode project files
