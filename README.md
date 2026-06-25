# Handshaker Reborn

Handshaker Reborn is a native macOS app for importing photos and videos from Android devices over ADB.

The app is built with SwiftUI, bundles `adb` inside the DMG release, and is designed for large Android media libraries where Camera folders may contain thousands of files.

## Features

- Native macOS SwiftUI interface.
- Supports macOS 14.0 and later, including macOS 14.8.
- Bundled `adb`; users do not need to install Android platform-tools separately.
- Android device detection with clear connection and authorization states.
- Real phone album discovery from common media locations.
- Finder-style media grid.
- Lazy loading for large albums.
- Recent photos and videos appear first.
- Image and video thumbnail support.
- Single selection, Command-click multi-select, Shift-click range select, select loaded, and clear selection.
- Finder folder picker before transfer.
- System-language UI:
  - Simplified Chinese for all Chinese locales, including Traditional Chinese systems.
  - English for all other languages.

## Installation

Download the latest DMG from [GitHub Releases](https://github.com/radonyl/Handshaker-Reborn/releases), open it, and launch `ADB Pull Photos.app`.

If macOS warns that the app is from an unidentified developer, open it from Finder with Control-click, then choose Open.

## Android Setup

1. Enable Developer Options on the Android phone.
2. Enable USB debugging.
3. Connect the phone to the Mac with a USB cable.
4. When the phone shows the USB debugging authorization prompt, choose Allow.
5. Open the app and click Refresh if the device does not appear immediately.

## Supported Media

Images:

- `jpg`
- `jpeg`
- `png`
- `webp`
- `heic`
- `gif`

Videos:

- `mp4`
- `mov`
- `mkv`
- `3gp`
- `webm`

## Build Locally

Open the package in Xcode:

```bash
open Package.swift
```

Or build from Terminal:

```bash
swift build
```

Package a local DMG:

```bash
Scripts/package_app.sh
```

The packaging script expects an `adb` executable. By default it uses `command -v adb`. To package with a specific `adb` binary:

```bash
ADB_SOURCE=/path/to/adb Scripts/package_app.sh
```

## GitHub Release Automation

This repository includes a GitHub Actions workflow that builds and publishes a DMG from macOS runners.

Release options:

- Push a tag such as `v0.1.0`.
- Or run the `Build and Release DMG` workflow manually from the Actions tab.

The workflow:

1. Checks out the repository.
2. Downloads Android platform-tools from Google's official distribution URL.
3. Builds the Swift package on `macos-14`.
4. Bundles `adb` into the app.
5. Creates a signed local app bundle with ad-hoc signing.
6. Generates a DMG.
7. Uploads the DMG as a workflow artifact.
8. Creates or updates a GitHub Release with the DMG attached.

## Current Limitations

- Cross-album selection and transfer are not supported yet.
- Visible thumbnails are cached locally.
- Transfer history persistence is not yet migrated to the Swift version.

## License

No open-source license has been declared yet. All rights are reserved unless a license is added by the repository owner.
