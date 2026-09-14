# Cove — App Store listing copy

All fields counted against App Store Connect limits.

---

## Subtitle  (28 / 30)

Your Jellyfin films, offline

---

## Promotional text  (140 / 170)

Your films and shows from your own Jellyfin server. Real downloads for the flight, a library that browses offline, and nothing phoning home.

---

## Keywords  (96 / 100)

**Option A — includes the Jellyfin name:**

jellyfin,self hosted,media server,stream,offline,download,movies,series,tv,player,nas,library

**Option B — no third-party trademarks:**

self hosted,media server,stream,offline,download,movies,series,player,nas,library,video,tv,shows

Notes: no spaces after commas (each costs a character). No plurals Apple already
stems. `plex` and `emby` deliberately omitted — competitor trademarks in the
keyword field are a known rejection trigger. If "Jellyfin" ends up in your app
name or subtitle, drop it from keywords; it is already indexed and the
characters are better spent elsewhere.

---

## Description  (1857 / 4000)

Cove is a player for your own Jellyfin server. Your films and your shows, on your iPhone and iPad, with nothing in between.

No accounts. No subscriptions. No middleman. Cove talks to your server and to nobody else.

YOUR WHOLE LIBRARY
Films, series and episodes, all where you expect them, and all of it mirrored on your device so browsing and search work with no connection at all. Pick up exactly where you stopped. Search everything at once, then narrow by decade, rating, watched state or favorites without leaving your results.

VIDEO DONE PROPERLY
Native playback with Picture in Picture and AirPlay. Switch audio tracks and subtitles mid-scene, and style subtitles so you can actually read them, including size, color and background. Skip intros and credits automatically, or set your own skip intervals and default playback speed.

TAKE IT WITH YOU
Download anything, whether that is a film or a whole season, and watch with no connection at all. Downloads keep going in the background, can be held to Wi-Fi only, and bring their artwork and metadata along so your library still looks like your library offline. Anything you watched while offline syncs back when you reconnect.

TUNED TO YOUR CONNECTION
Separate quality settings for Wi-Fi and cellular, so a 4K remux never quietly eats your data plan. See exactly what is using space, and clear it in one place.

ON YOUR HOME SCREEN
A widget for Continue Watching or Next Up, in three sizes.

MADE FOR THE PLATFORM
Built in SwiftUI. Dynamic Type, VoiceOver, Reduce Motion and Dark Mode are supported because they should be, not as an afterthought.

REQUIRES A JELLYFIN SERVER
Cove is a client, not a server and not a streaming service. You will need your own Jellyfin server (10.9 or later) and an account on it. Cove is an independent app, not affiliated with or endorsed by the Jellyfin project.

---

## Deliberately not claimed

Verified against the code, not `Cove/README.md` (which is aspirational):
CarPlay, Chromecast, SharePlay and multi-server switching are **not** in the
app. `ServerRepository.fetchAll()` exists but there is no UI to add or switch
servers. tvOS and Mac are excluded — the app target is iPhone/iPad only.

## Before you submit

1. **Demo server.** Guideline 2.1 rejects self-hosted clients a reviewer cannot
   sign in to. Put a reachable Jellyfin instance and credentials in App Review
   notes.
2. **The Jellyfin name.** Apple sometimes asks for written authorization when a
   third-party mark appears in metadata. Have their trademark policy to hand.
3. **Privacy label.** The description promises "nothing phoning home" twice.
   The nutrition label must say Data Not Collected or it is a rejection.
