# SANIVA release history

## 1.4 — 21 August 2026

- Added the bundled `saniva-scan` read-only Terminal command with text and JSON output.
- Added a clean white-background SANIVA master logo.
- Replaced the in-app wordmark with a true transparent-background asset.
- Kept `SANIVA.app` as the only application bundle and continued in-place version updates.

## 1.3 — 21 August 2026

- Reorganized the interface into Overview, Duplicates, Safe Cleanup, Applications, and Settings.
- Added a complete duplicate-review workflow with exact SHA-256 verification.
- Added file size, location, modification date, preview, and Reveal in Finder controls.
- Added per-file selection while protecting one keeper in every duplicate set.
- Added recoverable Move to Trash behavior for selected duplicates.
- Added scan phases, progress, cancellation, examined-file totals, inaccessible-file reporting, and elapsed time.
- Unified the product, executable, bundle identifier, and icon under the SANIVA identity.
- Added a dedicated square macOS application icon.
- Added automated duplicate-safety checks and macOS 14/15 CI configuration.
- Added an offline privacy policy and Developer ID/notarization release tooling.

## 1.2 — 21 August 2026

- Made SwiftUI the canonical implementation.
- Ported duplicate scanning, app removal, all-user scanning, Help, and weekly reminders.
- Added folder-scoped duplicate scanning and two-stage exact-content comparison.

## 1.1 — 16 August 2026

- Added the original native storage overview, safe cleanup, duplicate reporting, app removal, and all-user read-only scan.
