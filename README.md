# Xiaoya Player

**English** | [简体中文](README.zh-CN.md)

A clean, full-featured cross-platform media player for **Emby** and **Jellyfin**, built with **Flutter + MPV** (via [media_kit](https://github.com/media-kit/media-kit)).

One codebase, six targets: **macOS · Windows · Linux · Android · Android TV · iOS**.

## Highlights

- **MPV playback engine** — direct-plays virtually every container/codec (MKV, HEVC, EAC3, DTS, …) with hardware decoding. No server-side transcoding needed.
- **Emby & Jellyfin** — both servers share the same API family; one client handles either. Multi-server management with one-tap switching.
- **Progress sync** — playback position is reported to the server every 10 seconds and on exit, so you can pick up on any other device.
- **Auto play next** — episodes continue automatically, across season boundaries.
- **Android TV ready** — leanback launcher entry, D-pad focus navigation with poster highlight, remote key mapping, 10-foot typography, overscan-safe margins.
- **LAN QR pairing** — no more typing passwords with a remote: the TV shows a QR code, your phone opens a local form, submits credentials, and the TV logs in. Works with *any* server version (no Quick Connect required).
- **Comfortable UI** — Material 3, calm blue-teal palette, light/dark/system themes.

## Features

| Area | Details |
|---|---|
| Home | Continue Watching (one-tap resume), latest additions per library (lazy-loaded as you scroll) |
| Browse | Grid with infinite scrolling, sort by name / date added / year / rating |
| Search | Debounced full-library search |
| Details | Movie resume/restart, season & episode browser, favorites |
| Player | Audio track / subtitle switching (embedded **and** external Emby subtitles), playback speed, double-tap seek, fullscreen |
| TV remote | OK = play/pause · Left/Right = ±10 s · Up/Down = previous/next episode · Menu = subtitle/audio/speed panel |
| Servers | Multiple servers, persistent sessions, re-login, LAN QR pairing |

## Install

Grab the latest build for your platform from [**Releases**](../../releases):

| Platform | Artifact | Notes |
|---|---|---|
| Android / Android TV | `xiaoya-*-android.apk` | `adb install` or sideload; TV launcher entry included |
| macOS | `xiaoya-*-macos.zip` | Unsigned — right-click → Open on first launch |
| Windows | `xiaoya-*-windows.zip` | Unzip and run `xiaoya.exe` |
| Linux | `xiaoya-*-linux.tar.gz` | Requires `libmpv`: `sudo apt install libmpv2 mpv` |

## Quick start

1. Launch the app → **Add Server**.
2. Enter your Emby/Jellyfin address (`https://host:port`), username and password — or on TV, hit **Pair via phone QR** and fill the form on your phone.
3. Browse and play. Progress syncs back to your server automatically.

## Build from source

```bash
git clone https://github.com/hanshengcc/xiaoya-player.git
cd xiaoya-player
flutter pub get

flutter run -d macos      # or windows / linux / android / ios / chrome
flutter build apk --release
```

Platform notes:

- **Linux**: `sudo apt install libmpv-dev mpv ninja-build libgtk-3-dev`
- **macOS/iOS**: full Xcode + CocoaPods required
- **Web** builds run but are UI-preview only (browsers can't decode MKV/HEVC, and cross-origin servers need CORS)

## Architecture

```
lib/
├── api/            # Emby/Jellyfin REST client + models
├── state/          # App state: servers, session, theme, TV mode (persisted)
├── pages/          # servers / home / library / detail / search / player / settings / pairing
├── widgets/        # poster card (focus-aware), horizontal section row
└── utils/          # TV detection, LAN pairing HTTP server, formatting
```

- **Playback**: `media_kit` wraps libmpv on every platform; a permissive device profile keeps the server from transcoding.
- **State**: lightweight `provider` + `shared_preferences`.
- **TV mode**: auto-detected via `UiModeManager` on Android, manual toggle everywhere else.

## License

[MIT](LICENSE)
