# DBS Annotator — Tablet (Flutter)

Touch-first **iPadOS + Android tablet** companion to the Qt desktop app. Fully
**offline**; reads/writes the **same BIDS-named TSV files** as the desktop, so
data moves between the two via Files / iCloud / SharePoint / email — no server.

The desktop app (`src/dbs_annotator/`) is untouched and remains the **source of
truth** for the schema and clinical rules; this app consumes that contract from
`schema/*.json` (generated at the repo root) and a parity test fails if they drift.

## Status / roadmap

- **v1 (this scaffold):** app shell + **annotations-only** workflow (create
  timestamped notes → export BIDS `task-notes` TSV via the OS share sheet).
- **v1.1:** longitudinal review (import session TSVs → compare → PDF via `pdf`
  package + timeline via `fl_chart`).
- **v2:** full Complete Workflow incl. the interactive electrode viewer
  (port the state machine from `models/electrode_viewer.py`; rebuild rendering
  + tap hit-testing with a Flutter `CustomPainter`).

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.4+).
- The generated contract at repo root: run once from the repo root
  `uv run python scripts/generate_schema_json.py` (already committed; the
  parity test reads `../schema/tsv_schema.json`).

## First-time setup

The committed sources here are `pubspec.yaml`, `lib/`, and `test/`. The native
host projects (`android/`, `ios/`) are generated boilerplate — create them once:

```bash
cd tablet
# Generates android/ + ios/ around the existing lib/pubspec (does not touch lib/).
flutter create --platforms=android,ios --org ch.wysscenter --project-name dbs_annotator_tablet .
# Bundle the generated contract as assets (single source is repo-root schema/).
mkdir -p assets/schema && cp ../schema/*.json assets/schema/
flutter pub get
```

## Develop / test / run

```bash
cd tablet
flutter test          # runs schema-parity + TSV round-trip tests
flutter run           # on a connected iPad/Android tablet or emulator
flutter analyze       # lints
```

## Build & release (see .github/workflows/tablet-release.yml)

Tag `tablet-vX.Y.Z` to trigger the pipeline. Deployment model:

- **Android:** signed **APK attached to the GitHub Release** — users sideload it
  (mirrors the desktop app's GitHub-Releases model). `.aab` is also built for a
  future Google Play track.
- **iPadOS:** uploaded to **TestFlight** (Apple has **no GitHub-sideload path**
  for iOS). Requires an Apple Developer account — **waivable for nonprofits**
  (Wyss Center): enroll as an organization + D-U-N-S number + apply for the fee
  waiver. The GitHub Release notes link to the TestFlight invite.

Scale-up later with the same artifacts: `.aab` → Google Play, TestFlight build →
App Store, `.ipa`/`.aab` → MDM (Apple Business Manager / Android Enterprise).

## Layout

```
tablet/
  lib/
    core/        # pure Dart domain contract (TSV, BIDS, annotation model)
    ui/          # touch-first screens
    main.dart
  test/          # schema-parity + round-trip golden tests
  pubspec.yaml
```
