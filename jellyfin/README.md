# Cove

A premium media client for Jellyfin servers, built natively in Swift for iOS, iPadOS, and macOS.

Cove aims to be a best-in-class music player and media experience — think Apple Music meets Infuse, powered by your own Jellyfin server. Great offline support, beautiful UI, and a server-agnostic architecture designed to support additional media servers (Plex, Navidrome, etc.) in the future.

## Key Goals

- **Music-first** — full-featured music player with gapless playback, queue management, background audio, and a persistent Now Playing bar
- **Video done right** — movies and TV shows with native AVPlayer, PiP, AirPlay, subtitle support, and continue watching
- **Offline-first** — download music, movies, and TV shows for offline playback with full metadata and artwork
- **Multi-platform** — adaptive UI across iPhone, iPad, and Mac (tvOS architecture-ready)
- **Extensible** — server-agnostic abstraction layer so new media server backends can be added without touching the UI or playback engine

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

## Status

Early development. See [`.agents/ARCHITECTURE.md`](.agents/ARCHITECTURE.md) for the full design plan.