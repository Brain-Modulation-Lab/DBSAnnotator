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

> **Keep the bundled assets in sync.** The app loads contracts from
> `assets/schema/*.json` at runtime, but `flutter test` reads the repo-root
> `../schema/*.json`. If those two drift (e.g. after regenerating the schema),
> the app can show stale/missing data while tests still pass. Whenever
> `schema/*.json` changes, re-copy it: `cp ../schema/*.json assets/schema/`
> (the release CI does this automatically before every build).

## First-time setup

The committed sources here are `pubspec.yaml`, `lib/`, and `test/`. The native
host projects (`android/`, `ios/`) are generated boilerplate — create them once:

```bash
cd app
# Generates android/ + ios/ around the existing lib/pubspec (does not touch lib/).
flutter create --platforms=android,ios --org ch.wysscenter --project-name dbs_annotator .
# Bundle the generated contract as assets (single source is repo-root schema/).
mkdir -p assets/schema && cp ../schema/*.json assets/schema/
flutter pub get
```

## Report fonts (Unicode PDF)

The session report contains `µs` and verbatim clinical notes (arbitrary
Unicode); dart_pdf's built-in Helvetica is ASCII-only. Drop **IBM Plex Sans**
(OFL, redistributable) into `assets/fonts/` — the loader falls back to Helvetica
if absent (tests pass either way; only Unicode glyphs need it):

The loader needs exactly these two names:

```
app/assets/fonts/IBMPlexSans-Regular.ttf
app/assets/fonts/IBMPlexSans-Bold.ttf
```

Get the **static** TTFs from <https://fonts.google.com/specimen/IBM+Plex+Sans>
("Get font" -> download the zip -> the `static/` folder) or from
<https://github.com/IBM/plex/releases>. Do NOT hot-link a `raw.githubusercontent`
path: google/fonts has moved IBM Plex Sans to a variable font, so the old static
path 404s -- and a 404 still writes a file, because GitHub's error page is ~300 KB
of HTML that a "is the file big enough?" check happily accepts.

**Verify what you actually downloaded** (PowerShell). A TrueType font starts with
the bytes `00 01 00 00`; HTML starts with newlines or `<`:

```powershell
Get-ChildItem app/assets/fonts/*.ttf | ForEach-Object {
  $b = [System.IO.File]::ReadAllBytes($_.FullName)[0..3]
  "{0}: {1}" -f $_.Name, (($b | ForEach-Object { $_.ToString('x2') }) -join ' ')
}
```

`00 01 00 00` (or `4f 54 54 4f` for an OpenType/CFF build) is a font. Anything
else -- `0a 0a 0a 0a`, `3c 21 44 4f` -- is not, and the loader will correctly
ignore it and fall back to Helvetica.

## Develop / test / run

```bash
cd app
flutter test          # runs schema-parity + TSV round-trip tests
flutter run           # on a connected iPad/Android tablet or emulator
flutter analyze       # lints
```

## Build & release (see .github/workflows/app-release.yml)

Tag `app-vX.Y.Z` to trigger the pipeline. Deployment model:

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
app/
  lib/
    core/        # pure Dart domain contract (TSV, BIDS, annotation model)
    ui/          # touch-first screens
    main.dart
  test/          # schema-parity + round-trip golden tests
  pubspec.yaml
```
