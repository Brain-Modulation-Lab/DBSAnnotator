# Contributing to DBS Annotator

Contributions are welcome. This is research software for deep brain stimulation
programming, so correctness and honesty about what the data supports matter more
here than most places — see *Clinical care* below.

## Scope

Everything here is the Flutter app: `lib/` for source, `test/` for tests.

If you change the TSV format, change `schema/*.json` and `assets/schema/*.json`
together — both are committed so that a clone builds with nothing generated.

Some doc comments in `lib/` cite a Python module as `dbs_annotator/<module>.py`.
Those name the reference implementation each algorithm was checked against; the
code is on the `qt-legacy` branch. Several of those comments record a
*deliberate* divergence, so keep them when editing nearby.

## Quick start

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart 3.4+). From the repository root:

```bash
flutter pub get
flutter test
flutter analyze
```

Then:

1. Fork the repository and branch: `git switch -c feature/your-feature-name`
2. Make your change, with tests
3. `flutter analyze && flutter test` must both be clean
4. Open a pull request

## What we look for

- **Tests that would have caught the bug.** A test asserting only that a
  function runs is worth little; one pinning the value it produces is worth a
  lot. Several tests in this repo exist because a reviewer computed the expected
  numbers independently and they disagreed with the code.
- **Comments that explain *why*.** The codebase deliberately diverges from the
  Qt original in a number of places, and each divergence carries a comment
  saying what was wrong with the original. Preserve that reasoning.
- **`flutter analyze` clean.** No new warnings, no `// ignore:` without a reason.

## Clinical care

This app produces documents that go into a patient record. Two rules follow from
that, and both have already caused real changes here:

- **Never assert what the data does not support.** The reports say "last recorded
  configuration", not "final settings", because nothing in the TSV records that a
  clinician confirmed a choice. The block ranking refuses to run at all when no
  scale targets have been set, rather than inventing them.
- **Never lose data silently.** If a character cannot be rendered, the export
  says so. If a file cannot be written, the write is atomic and the old file
  survives. A silent partial success is worse than a loud failure.

## Documentation

Documentation lives in `docs/` (Sphinx, reStructuredText) and is published to
Read the Docs. Screenshots are generated from Flutter widget tests — do not edit
them by hand.

## Getting help

Open an issue, or start a discussion. For anything that looks like a clinical
safety concern, please say so explicitly in the issue title.

## License

By contributing you agree that your contribution is licensed under the MIT
license, as in [LICENSE](LICENSE).
