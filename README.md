# DBS Annotator

Record deep brain stimulation programming sessions at the bedside, and get
analysis-ready data out.

DBS Annotator captures what was actually done during a DBS programming session —
the stimulation parameters tried on each contact, the clinical and session scale
ratings at each configuration, side effects, and free-text notes — and writes it
to **BIDS-named TSV files** that go straight into analysis. It also produces
clinician-readable **PDF and Word reports** for the patient record.

It runs **fully offline**. No account, no server, no telemetry. Tablet-first
(iPadOS and Android) with desktop builds for Linux, Windows and macOS.

## Why

Vendor programming devices record what the device needs, not what research
needs, and they do not export data anyone can pool across patients or sites.
The alternative in practice is paper notes, which do not survive analysis. So
sessions get documented twice, inconsistently, and the parameter–response
relationship — the whole point of a titration session — is the part that gets
lost.

This tool records that relationship as it happens, in one format, with the
timestamps intact.

## Repository layout

```
lib/                 the Flutter application (Dart)
test/                352 tests
assets/              bundled schema contract, fonts, app icon
android/ ios/ linux/ macos/ windows/
schema/              the machine-readable domain contract (TSV columns,
                     BIDS naming, stimulation limits, electrode models)
docs/                documentation source (Read the Docs)
paper/               JOSS paper
```

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart 3.4+). From the repository root:

```bash
flutter pub get
flutter test        # 352 tests, no device needed
flutter analyze
flutter run         # on a connected tablet, emulator, or desktop
```

Nothing needs generating first. The schema contract is committed, so a fresh
clone builds and tests immediately.

## The four workflows

| Workflow | What it records |
|---|---|
| **Complete workflow** | Stimulation parameters, electrode contact selection, clinical and session scales, side effects, notes — the full titration session |
| **Annotations only** | Timestamped free-text notes and nothing else |
| **Single session report** | Open an existing TSV, get its report — no authoring |
| **Longitudinal review** | Several sessions of one patient, compared across visits |

## Output

Data is written as BIDS-named TSV, one row per (block, scale), so it pivots
directly:

```python
df = pd.read_csv(path, sep="\t")
df.pivot_table(index=["session_ID", "block_ID"],
               columns="scale_name", values="scale_value")
```

Reports come out as PDF and Word, both built from the same numbers so they
cannot disagree. The full format reference is in the
[documentation](https://dbsannotator.readthedocs.io/).

## Report fonts (optional, but recommended)

The PDF exporter falls back to Helvetica, which is Latin-1 only — so a curly
quote or an accented character in a clinical note becomes `?`. The app warns you
when that happens. To get full Unicode, drop these two files into
`assets/fonts/`:

```
assets/fonts/IBMPlexSans-Regular.ttf
assets/fonts/IBMPlexSans-Bold.ttf
```

Get the **static** TTFs from
<https://fonts.google.com/specimen/IBM+Plex+Sans> ("Get font", then the
`static/` folder in the zip) or from <https://github.com/IBM/plex/releases>.

Do **not** hot-link a `raw.githubusercontent` path — google/fonts has moved IBM
Plex Sans to a variable font, so the old static path 404s, and a 404 still
writes a file: GitHub's error page is ~300 KB of HTML, which sails past any
"is the file big enough?" check. Verify the magic bytes instead:

```powershell
Get-ChildItem assets/fonts/*.ttf | ForEach-Object {
  $b = [System.IO.File]::ReadAllBytes($_.FullName)[0..3]
  "{0}: {1}" -f $_.Name, (($b | ForEach-Object { $_.ToString('x2') }) -join ' ')
}
```

`00 01 00 00` is a TrueType font (`4f 54 54 4f` for OpenType/CFF). Anything else
is not, and the loader will correctly ignore it.

## Releases

Tag `app-vX.Y.Z` to trigger
[the pipeline](.github/workflows/ci.yml). Android ships a signed APK on
the GitHub Release; iPadOS goes to TestFlight (Apple has no sideload path);
Linux, Windows and macOS bundles are built as workflow artifacts. Per-OS app
store distribution is planned.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Citing

If you use DBS Annotator in published work, please cite it — see
[CITATION.cff](CITATION.cff).

## License

MIT. See [LICENSE](LICENSE).
