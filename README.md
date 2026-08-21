# SANIVA 1.4

SANIVA is a permission-first macOS storage utility. `SANIVA.app` is the single maintained application bundle and is replaced in place for each new version. Release changes are recorded in `CHANGELOG.md` and displayed under Settings → Updates.

## Download and install

1. Open the repository’s **Releases** page and download `SANIVA-1.4-macOS-arm64.zip`.
2. Unzip it and move `SANIVA.app` into Applications.
3. On first launch, Control-click or right-click the app, choose **Open**, then confirm **Open**.

The current public build supports Apple-silicon Macs running macOS 14 Sonoma or later. It is ad-hoc signed and not Apple-notarized, so opening it normally may show a Gatekeeper warning. Never disable Gatekeeper globally; use the one-app right-click → Open flow above. Developer ID signing and notarization are planned for a later release.

Verify the ZIP after downloading:

```zsh
shasum -a 256 SANIVA-1.4-macOS-arm64.zip
```

## Features

- Shows used, available, and total Mac storage.
- Reviews and clears only the current user’s Trash and app-cache contents.
- Finds exact content-identical files, lets users review every match, and moves only selected copies to recoverable macOS Trash.
- Removes explicitly selected `.app` bundles after a final confirmation.
- Protects macOS system apps and SANIVA itself.
- Performs an optional administrator-approved, read-only scan of all users’ Trash and caches.
- Schedules an optional Monday 10 AM storage-review notification.
- Explains every operation in built-in Help.

Cleanup and app removal are permanent, but neither can occur without an explicit selection and confirmation. Duplicate scanning is read-only; its separately confirmed cleanup action moves files to recoverable Trash. All-user scanning is report-only.

## Requirements

- macOS 14 Sonoma or later
- Xcode or matching Xcode Command Line Tools with Swift 6 support

## Run from source

```zsh
swift run SANIVA
```

## Build the app

```zsh
chmod +x build-app.sh "Run Saniva Cleaner.command"
./build-app.sh
open "SANIVA.app"
```

`build-app.sh` updates the single canonical `SANIVA.app` bundle and applies a local ad-hoc signature.

## Project layout

- `Sources/SpaceSentry/` — canonical SwiftUI application
- `Sources/SANIVACore/` — shared duplicate-scanning engine
- `Sources/SANIVACLI/` — read-only Terminal scanner
- `Resources/` — app metadata, icon, and logo assets

There are no external package dependencies, services, analytics, or API keys.

## Terminal scanner

```zsh
swift run saniva-scan ~/Documents
swift run saniva-scan --json ~/Documents ~/Downloads
```

The command reports matches and never moves or deletes files.
