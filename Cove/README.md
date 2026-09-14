# Cove

A premium video client for Jellyfin servers, built natively in Swift for iOS and iPadOS.

Cove aims to be a best-in-class films-and-shows experience — think Infuse, powered by your own Jellyfin server. Great offline support, beautiful UI, and a server-agnostic architecture designed to support additional media servers (Plex, Navidrome, etc.) in the future.

## Key Goals

- **Video done right** — movies and TV shows with native AVPlayer, PiP, AirPlay, subtitle support, and continue watching
- **Offline-first** — download movies and TV shows for offline playback with full metadata and artwork; the whole library is mirrored locally so browsing works without a connection
- **Multi-platform** — adaptive UI across iPhone, iPad, Mac, and Apple TV, with a platform capability system that makes adding new platforms trivial
- **Extensible** — server-agnostic abstraction layer so new media server backends can be added without touching the UI or playback engine

## Platforms

| Platform | Status | Navigation |
|----------|--------|------------|
| iOS | ✅ Primary | Bottom tab bar |
| iPadOS | ✅ Adaptive | Sidebar layout |
| macOS | ✅ Native SwiftUI | Sidebar layout |
| tvOS | 🔧 Core-ready | Top tab bar with focus navigation |
| watchOS | 📐 Architecture-ready | Deferred |

## Tech Stack

| Layer | Choice |
|---|---|
| UI | SwiftUI |
| Architecture | MVVM + @Observable |
| Networking | URLSession + async/await |
| Database | GRDB (SQLite) |
| Playback | AVPlayer / AVQueuePlayer |
| Image Loading | Nuke |
| Project Structure | SPM multi-module |
| Platform Abstraction | `PlatformCapabilities` environment + cross-platform view modifiers |

## Status

Early development. See [`.agents/ARCHITECTURE.md`](.agents/ARCHITECTURE.md) for the full design plan.