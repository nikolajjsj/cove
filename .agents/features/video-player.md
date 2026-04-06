# Video Player — Universal Format Support

> **Status**: Approved design, ready for implementation
> **Scope**: Fix server communication so the Jellyfin server correctly handles remuxing and transcoding, enabling playback of virtually all video formats through the existing AVPlayer pipeline

---

## Overview

The current video player uses AVPlayer but fails to play many common video files (MKV, AVI, etc.) because the app does not send a `DeviceProfile` to the Jellyfin server when requesting playback info. Without knowing the client's capabilities, the server defaults to direct play — handing back raw files that AVPlayer cannot decode.

The fix is **not** to add a third-party player (VLCKit, libmpv). Instead, we lean on the Jellyfin server's built-in FFmpeg pipeline by sending an accurate `DeviceProfile` with every playback request. The server then makes the right decision:

| Server Decision | When | CPU Cost | Quality Loss |
|---|---|---|---|
| **DirectPlay** | Container + codecs all AVPlayer-compatible (e.g. MP4 H.264+AAC) | Zero | None |
| **DirectStream** (remux) | Codecs compatible but container isn't (e.g. MKV H.264+AAC → MP4) | Near-zero | None |
| **Transcode** | Codecs incompatible (e.g. VP9, DTS → H.264+AAC via HLS) | Heavy | Minimal (server re-encodes) |

This approach requires **zero new client-side dependencies**, no binary size increase, and no licensing concerns.

---

## Problem Analysis

### Root Cause 1: No DeviceProfile in PlaybackInfo Request

The current `PlaybackInfoRequest` only sends `userId`:

```swift
private struct PlaybackInfoRequest: Encodable, Sendable {
    let userId: String
}
```

The Jellyfin `POST /Items/{id}/PlaybackInfo` API accepts a full `DeviceProfile` with `DirectPlayProfiles`, `TranscodingProfiles`, and `ContainerProfiles`. Without it, the server cannot make informed playback decisions.

### Root Cause 2: DirectPlay and DirectStream Treated Identically

The current `streamURL()` function treats `supportsDirectPlay` and `supportsDirectStream` as the same thing, always requesting with `static=true`:

```swift
if source.supportsDirectPlay == true || source.supportsDirectStream == true,
    let url = client.videoStreamURL(
        itemId: item.id.rawValue, mediaSourceId: sourceId, container: source.container)
```

But they are different:
- **DirectPlay** (`static=true`) — stream the file bit-for-bit as-is
- **DirectStream** (`static=false`) — server remuxes the container on-the-fly

When the server says "DirectStream supported but not DirectPlay" (e.g. MKV with H.264), the app still requests the raw file with `static=true`, bypassing the server's remux — and AVPlayer chokes.

### Root Cause 3: Downloads Use Raw File Endpoint

Downloads use `/Items/{id}/Download`, which returns the original file regardless of format. An MKV download is stored as-is, and offline playback via `playLocal()` feeds it to AVPlayer, which cannot play it.

---

## 1. DeviceProfile Redesign

### Current Model (flat, insufficient)

```swift
public struct DeviceProfile: Sendable {
    let name: String
    let maxStreamingBitrate: Int?
    let supportedVideoCodecs: [String]
    let supportedAudioCodecs: [String]
    let supportedContainers: [String]
    let supportsDirectPlay: Bool
    let supportsDirectStream: Bool
    let supportsTranscoding: Bool
}
```

### New Model (matches Jellyfin API)

```swift
public struct DeviceProfile: Codable, Sendable {
    public let name: String
    public let maxStreamingBitrate: Int?
    public let directPlayProfiles: [DirectPlayProfile]
    public let transcodingProfiles: [TranscodingProfile]
    public let containerProfiles: [ContainerProfile]
    public let codecProfiles: [CodecProfile]
    public let subtitleProfiles: [SubtitleProfile]
}

public struct DirectPlayProfile: Codable, Sendable {
    public let container: String        // e.g. "mp4,m4v,mov"
    public let type: ProfileType        // .video or .audio
    public let videoCodec: String?      // e.g. "h264,hevc"
    public let audioCodec: String?      // e.g. "aac,mp3,alac,ac3,eac3"
}

public struct TranscodingProfile: Codable, Sendable {
    public let container: String        // e.g. "ts"
    public let type: ProfileType        // .video
    public let videoCodec: String       // e.g. "h264"
    public let audioCodec: String       // e.g. "aac,mp3"
    public let `protocol`: String       // e.g. "hls"
    public let context: String          // "Streaming" or "Static"
    public let maxAudioChannels: String? // e.g. "2" or "6"
    public let breakOnNonKeyFrames: Bool?
    public let copyTimestamps: Bool?
}

public struct ContainerProfile: Codable, Sendable {
    public let type: ProfileType
    public let container: String
    public let conditions: [ProfileCondition]?
}

public struct CodecProfile: Codable, Sendable {
    public let type: CodecType          // .video or .videoAudio
    public let codec: String?           // e.g. "h264"
    public let conditions: [ProfileCondition]?
}

public struct SubtitleProfile: Codable, Sendable {
    public let format: String           // e.g. "srt", "vtt", "ass", "pgs"
    public let method: SubtitleMethod   // .external, .embed, .encode (burn-in)
}

public enum ProfileType: String, Codable, Sendable {
    case video = "Video"
    case audio = "Audio"
    case photo = "Photo"
}

public enum CodecType: String, Codable, Sendable {
    case video = "Video"
    case videoAudio = "VideoAudio"
    case audio = "Audio"
}

public enum SubtitleMethod: String, Codable, Sendable {
    case encode = "Encode"      // Burn into video stream (ASS/PGS)
    case embed = "Embed"        // Embedded in container
    case external = "External"  // Side-loaded file (SRT/VTT)
    case hls = "Hls"            // Via HLS manifest
    case drop = "Drop"          // Discard
}

public struct ProfileCondition: Codable, Sendable {
    public let condition: ProfileConditionType
    public let property: ProfileConditionProperty
    public let value: String?
    public let isRequired: Bool?
}

public enum ProfileConditionType: String, Codable, Sendable {
    case equals = "Equals"
    case notEquals = "NotEquals"
    case lessThanEqual = "LessThanEqual"
    case greaterThanEqual = "GreaterThanEqual"
}

public enum ProfileConditionProperty: String, Codable, Sendable {
    case audioChannels = "AudioChannels"
    case audioBitrate = "AudioBitrate"
    case videoBitrate = "VideoBitrate"
    case videoLevel = "VideoLevel"
    case width = "Width"
    case height = "Height"
    case refFrames = "RefFrames"
}
```

All `CodingKeys` use PascalCase to match the Jellyfin API JSON format (e.g. `DirectPlayProfiles`, `TranscodingProfiles`, `VideoCodec`, etc.).

---

## 2. AVPlayer Capability Profile

Conservative profile covering what AVPlayer reliably handles on iOS 18+ and macOS 15+.

### Direct Play Profiles

| Container | Video Codecs | Audio Codecs |
|---|---|---|
| `mp4`, `m4v`, `mov` | `h264`, `hevc` | `aac`, `mp3`, `alac`, `flac`, `ac3`, `eac3` |

### Transcoding Profile

| Container | Protocol | Video Codec | Audio Codec | Context |
|---|---|---|---|---|
| `ts` | `hls` | `h264` | `aac`, `mp3` | Streaming |

### Subtitle Profiles

| Format | Method |
|---|---|
| `srt` | External |
| `vtt` | External |
| `ass` | Encode (burn-in) |
| `ssa` | Encode (burn-in) |
| `pgs` | Encode (burn-in) |
| `pgssub` | Encode (burn-in) |
| `dvdsub` | Encode (burn-in) |
| `sub` | Encode (burn-in) |

### Profile Builder

```swift
extension DeviceProfile {
    /// Build the profile for the current Apple device.
    /// Conservative: only includes formats we are confident AVPlayer handles.
    static func appleDevice(
        name: String = "Cove",
        maxStreamingBitrate: Int = 120_000_000
    ) -> DeviceProfile
}
```

Both iOS and macOS share the same profile. The safe list is deliberately conservative — formats that AVPlayer *might* support on some hardware are excluded. This means some files that could theoretically direct-play will be remuxed or transcoded. This is acceptable: the server-side cost of an unnecessary remux is negligible, and correctness is more important than optimization.

The profile can be expanded over time as we gain confidence about additional format support.

---

## 3. PlaybackInfo Request Changes

### Updated Request Body

```swift
struct PlaybackInfoRequest: Encodable, Sendable {
    let userId: String
    let deviceProfile: DeviceProfile
    let autoOpenLiveStream: Bool
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let maxStreamingBitrate: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case deviceProfile = "DeviceProfile"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
    }
}
```

### Updated API Method

```swift
public func getPlaybackInfo(
    userId: String,
    itemId: String,
    profile: DeviceProfile
) async throws -> PlaybackInfoResponse
```

Default values for the boolean fields:
- `autoOpenLiveStream`: `true`
- `enableDirectPlay`: `true`
- `enableDirectStream`: `true`
- `enableTranscoding`: `true`

`maxStreamingBitrate` is taken from the profile.

---

## 4. Stream Resolution — Four-Branch Logic with Client-Side Safety Net

### Current (broken)

```
if directPlay OR directStream → videoStreamURL(static=true)
else if transcodingUrl exists → hlsStreamURL()
else → error
```

### New (correct)

The server's DirectPlay/DirectStream decisions are **not trusted blindly**. A client-side AVPlayer compatibility check validates that the container and codecs are actually playable before using the server's suggestion. If the server incorrectly suggests DirectPlay for an unsupported format (e.g. AVI/MPEG4), the client falls through to transcoding.

#### AVPlayer Compatibility Check

```swift
// Containers AVPlayer can handle
private static let avPlayerContainers: Set<String> = ["mp4", "m4v", "mov"]
// Video codecs AVPlayer can decode
private static let avPlayerVideoCodecs: Set<String> = ["h264", "hevc", "h265"]
// Audio codecs AVPlayer can decode
private static let avPlayerAudioCodecs: Set<String> = ["aac", "mp3", "alac", "flac", "ac3", "eac3"]

// Full check (container + codecs) — used for DirectPlay
static func isAVPlayerCompatible(container:, videoCodec:, audioCodec:) -> Bool

// Codec-only check — used for DirectStream (server remuxes container)
static func areCodecsAVPlayerCompatible(videoCodec:, audioCodec:) -> Bool
```

#### Resolution Flow

```
1. POST /Items/{id}/PlaybackInfo with DeviceProfile
2. Log raw server response (container, codecs, directPlay, directStream, transcodingUrl)
3. Run client-side AVPlayer compatibility check

   Branch 1 — DirectPlay:
     if supportsDirectPlay == true AND isAVPlayerCompatible():
       → videoStreamURL(static=true, container=source.container)
       → StreamInfo(playMethod: .directPlay)

   Branch 2 — DirectStream (remux):
     if supportsDirectStream == true AND areCodecsAVPlayerCompatible():
       → videoStreamURL(static=false)
       → StreamInfo(playMethod: .directStream)

   Branch 3 — Transcode (from initial response):
     if transcodingUrl != nil:
       → hlsStreamURL(transcodingPath)
       → StreamInfo(playMethod: .transcode)

   Branch 4 — Forced Transcode Retry:
     if format was NOT AVPlayer-compatible AND no transcodingUrl in initial response:
       → Re-request PlaybackInfo with enableDirectPlay=false, enableDirectStream=false
       → Forces server to provide a transcode URL
       → hlsStreamURL(retryTranscodingPath)
       → StreamInfo(playMethod: .transcode)

   else:
     → throw AppError.playbackFailed("Unable to resolve a playable stream")
```

This four-branch approach handles the common case where the server doesn't fully respect the DeviceProfile (e.g. older Jellyfin versions, misconfigured profiles) and would otherwise hand back a raw AVI/MKV/MPEG4 file that AVPlayer cannot open.

### videoStreamURL Changes

Add a `staticStream` parameter:

```swift
public func videoStreamURL(
    itemId: String,
    mediaSourceId: String,
    container: String? = nil,
    staticStream: Bool = true        // NEW: false for DirectStream (remux)
) -> URL?
```

When `staticStream` is `false`, omit the `static` query parameter (or set it to `"false"`), which signals the server to remux the stream into a compatible container.

---

## 5. StreamInfo Enrichment

### Current

```swift
public struct StreamInfo: Sendable {
    public let url: URL
    public let isTranscoded: Bool
    public let mediaStreams: [MediaStream]
    public let directPlaySupported: Bool
}
```

### New

```swift
public struct StreamInfo: Sendable {
    public let url: URL
    public let playMethod: PlayMethod
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let mediaStreams: [MediaStream]
    public let mediaSourceId: String?

    public var isTranscoded: Bool { playMethod == .transcode }
    public var directPlaySupported: Bool { playMethod == .directPlay }
}

public enum PlayMethod: String, Sendable {
    case directPlay
    case directStream
    case transcode
}
```

The `container`, `videoCodec`, and `audioCodec` fields are extracted from `MediaSourceInfo` and its `mediaStreams`. They serve two purposes:
1. Logging/debugging — when playback fails, we can log what format was attempted
2. Future use — if we ever add a client-side compatibility check or user-facing format info

`mediaSourceId` is needed for subtitle URL construction and playback reporting.

---

## 6. Download Flow — Compatible Format

### Current (broken)

```
downloadURL(for:) → /Items/{id}/Download → raw original file (MKV, AVI, etc.)
```

### New (correct)

Replace the raw download endpoint with the video stream endpoint, requesting a container AVPlayer can handle:

```swift
public func compatibleDownloadURL(
    itemId: String,
    mediaSourceId: String
) -> URL?
```

This builds a URL to `/Videos/{id}/stream` with:
- `static=false` — allows the server to remux if needed
- `mediaSourceId` — identifies the specific media source
- `container=mp4` — request an MP4 container
- No bitrate limit — original quality, only the container/codec changes if necessary
- `api_key` — authentication

### Download Resolution Flow

Before enqueuing a download, resolve the playback info to determine the optimal download strategy:

```
1. POST /Items/{id}/PlaybackInfo with DeviceProfile
2. Read server decision:

   if supportsDirectPlay == true:
       → use /Items/{id}/Download (raw file, already compatible)

   else if supportsDirectStream == true:
       → use /Videos/{id}/stream?static=false&mediaSourceId=X (server remuxes to MP4)

   else if supportsTranscoding == true:
       → use /Videos/{id}/stream?static=false&mediaSourceId=X (server transcodes)

   else:
       → throw error("This file cannot be downloaded in a compatible format")
```

### Changes to Provider

```swift
// Updated signature
public func downloadURL(for item: MediaItem, profile: DeviceProfile?) async throws -> URL

// Implementation queries PlaybackInfo first, then picks the right URL
```

### Changes to AppState.downloadItem()

Pass the device profile when resolving the download URL:

```swift
let profile = provider.deviceProfile()
let remoteURL = try await provider.downloadURL(for: item, profile: profile)
```

### Offline Playback

No changes needed to `playLocal()`. Downloaded files are now guaranteed to be in a format AVPlayer can handle (MP4 with compatible codecs), so `AVPlayer(url: localFileURL)` works as-is.

---

## 7. Error Handling

### New Callback on VideoPlaybackManager

```swift
/// Called when playback fails (e.g. AVPlayerItem status → .failed).
public var onPlaybackError: (@MainActor (MediaItem, Error) -> Void)?
```

Triggered from the existing `observePlayerItem` status observer when `item.status == .failed`.

### VideoPlayerCoordinator Error Surfacing

The coordinator already has an `error: PlaybackError?` property and `showError` binding. Wire the new `onPlaybackError` callback to set this error, which drives an alert in the UI:

```
Title: "Playback Error"
Message: "Unable to play {item.title}. Your server may not support transcoding this format."
Button: "OK" → dismiss player
```

### Logging

Add structured logging at each decision point in `streamURL()`:

```swift
logger.info("PlaybackInfo: method=\(playMethod) container=\(container) video=\(videoCodec) audio=\(audioCodec)")
```

This makes it easy to diagnose playback issues — the log shows exactly what the server decided and why.

---

## 8. Playback Reporting Fix

The current playback reporting sends `playMethod: "DirectPlay"` hardcoded in the progress/start/stop reports. With the three-branch logic, this needs to report the actual method:

| Play Method | Report Value |
|---|---|
| DirectPlay | `"DirectPlay"` |
| DirectStream | `"DirectStream"` |
| Transcode | `"Transcode"` |

This ensures the Jellyfin dashboard correctly shows what's happening per session.

---

## 9. What This Does NOT Change

- **AVPlayer remains the only player** — no VLCKit, no libmpv, no FFmpegKit
- **No new dependencies** — binary size unchanged
- **VideoPlaybackManager** — no structural changes, same AVPlayer lifecycle (only additions: diagnostic logging and `onPlaybackError` callback)
- **VideoRenderView** — untouched (same AVPlayerLayer wrapper)
- **VideoPlayerView** — untouched (same controls overlay, only addition: error callback wiring)
- **PiP, AirPlay, Now Playing** — all continue to work as-is (AVPlayer native features)
- **Audio playback** — completely unaffected
- **Subtitle track selection UI** — unchanged (tracks come from MediaSourceInfo as before)

---

## 10. Files Changed

| # | File | Change |
|---|---|---|
| 1 | `Models/DeviceProfile.swift` | **Rewrite** — new structure matching Jellyfin API (DirectPlayProfiles, TranscodingProfiles, SubtitleProfiles, etc.) with `appleDevice()` factory |
| 2 | `Models/StreamInfo.swift` | **Extend** — add `playMethod`, `container`, `videoCodec`, `audioCodec`, `mediaSourceId`; `isTranscoded`/`directPlaySupported` become computed properties |
| 3 | `Models/PlayMethod.swift` | **New** — `PlayMethod` enum (directPlay, directStream, transcode) |
| 4 | `JellyfinAPI/JellyfinAPIClient.swift` | **Edit** — update `PlaybackInfoRequest` to include DeviceProfile with PascalCase CodingKeys; update `getPlaybackInfo()` signature; add `getPlaybackInfoTranscodeOnly()` for forced transcode retry; add `staticStream` param to `videoStreamURL()`; add `compatibleDownloadURL()` method |
| 5 | `JellyfinProvider/JellyfinServerProvider.swift` | **Edit** — rewrite `streamURL()` with four-branch logic including client-side AVPlayer compatibility check and forced transcode retry; add `isAVPlayerCompatible()`/`areCodecsAVPlayerCompatible()` static methods; rewrite `deviceProfile()` to use `appleDevice()` factory; update `downloadURL()` to use compatible format; pass profile to `getPlaybackInfo()` |
| 6 | `PlaybackEngine/VideoPlaybackManager.swift` | **Edit** — add `onPlaybackError` callback; fire it from `observePlayerItem` on `.failed` status; add detailed diagnostic logging (NSError domain/code, underlying error, failure reason, failed URL) |
| 7 | `Cove/UI/Video/VideoPlayerCoordinator.swift` | **Edit** — update `playLocal()` for new `StreamInfo` init; improve `PlaybackError.localizedDescription` with user-friendly message |
| 8 | `Cove/UI/Video/VideoPlayerView.swift` | **Edit** — wire `onPlaybackError` in `setupAndPlay()` |
| 9 | `Cove/UI/Video/MovieDetailView.swift` | **Edit** — pass `provider.deviceProfile()` to download URL resolver |
| 10 | `Cove/AppState.swift` | **Edit** — pass `provider.deviceProfile()` to all `downloadURL()` calls |

---

## 11. What This Unlocks

After implementation, the following formats will play correctly (server handles conversion):

| Container | Video Codec | Audio Codec | Server Action |
|---|---|---|---|
| MP4/MOV with H.264+AAC | ✅ | ✅ | DirectPlay |
| MP4 with HEVC+AAC | ✅ | ✅ | DirectPlay |
| MP4 with H.264+AC3/EAC3 | ✅ | ✅ | DirectPlay |
| MKV with H.264+AAC | ✅ | ✅ | DirectStream (remux → MP4, near-zero cost) |
| MKV with HEVC+AAC | ✅ | ✅ | DirectStream (remux → MP4, near-zero cost) |
| MKV with H.264+DTS | ✅ | ❌ | Transcode audio only (DTS→AAC) |
| MKV with H.264+TrueHD | ✅ | ❌ | Transcode audio only |
| AVI with H.264+MP3 | ✅ | ✅ | DirectStream (remux → MP4) |
| Any container with VP9 | ❌ | — | Full transcode (VP9→H.264) |
| Any container with AV1 | ❌ | — | Full transcode (AV1→H.264) |
| Any container with MPEG-2 | ❌ | — | Full transcode |
| Any container with VC-1 | ❌ | — | Full transcode |

### Subtitles

| Format | Handling |
|---|---|
| SRT | Delivered as external VTT (server converts) |
| VTT | Delivered as external file |
| ASS/SSA | Burned into video stream by server |
| PGS/VobSub | Burned into video stream by server |

---

## 12. Trade-offs & Limitations

1. **Server dependency** — users with underpowered servers (Raspberry Pi, low-end NAS) will struggle with full transcodes. Remuxing is fine on any hardware. This is an accepted limitation; it matches the behavior of most Jellyfin clients.

2. **Transcode quality** — server-side transcoding is lossy. A VP9 file transcoded to H.264 will have generational quality loss. This is inherent to any transcode approach and is acceptable.

3. **Conservative profile** — some formats AVPlayer *might* handle (e.g. AC-3 in MKV on newer iOS versions) will be unnecessarily remuxed. This is by design: correctness over optimization. The profile can be expanded incrementally as we verify support.

4. **No client-side fallback** — if the server cannot transcode (FFmpeg missing, overloaded, etc.), playback fails with an error. There is no VLCKit fallback. This is the accepted trade-off for zero client-side dependencies.

5. **Download size** — transcoded downloads may differ in size from the original. Remuxed downloads are identical in size. No bitrate limit is applied; original quality is preserved where possible.

6. **Double PlaybackInfo request** — when the server incorrectly suggests DirectPlay for an AVPlayer-incompatible format and provides no transcodingUrl, a second request is made with forced transcoding. This adds latency (~one extra API call) for edge cases where the server doesn't respect the DeviceProfile. The common case (server respects profile) is unaffected.

---

## Implementation Order

1. **Models**: Rewrite `DeviceProfile.swift` with new structure; add `PlayMethod.swift`; extend `StreamInfo.swift`
2. **API Client**: Update `PlaybackInfoRequest` with DeviceProfile; update `getPlaybackInfo()` signature; add `staticStream` param to `videoStreamURL()`; add `compatibleDownloadURL()`
3. **Provider**: Rewrite `deviceProfile()` with accurate AVPlayer profile; rewrite `streamURL()` with three-branch DirectPlay/DirectStream/Transcode logic; update `downloadURL()` to resolve compatible format
4. **Playback Engine**: Add `onPlaybackError` callback to `VideoPlaybackManager`
5. **UI Wiring**: Wire error callback through `VideoPlayerCoordinator` → `VideoPlayerView`; pass device profile in download flows
6. **Testing**: Verify with MKV (H.264+AAC), MKV (H.264+DTS), MP4 (H.264+AAC), and a transcode-required format (VP9/AV1) against a test Jellyfin server