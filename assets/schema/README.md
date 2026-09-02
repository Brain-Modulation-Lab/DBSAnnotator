# Bundled schema contract

These four JSON files are the machine-readable domain contract — TSV columns, BIDS filename format,
stimulation limits and presets, electrode-model geometry — and they are **tracked in git**.

They are a bundled copy. The canonical copy is the repo-root `schema/`, because Flutter can only bundle
assets that live under the project directory, so the app needs its own copy under `assets/`.

Both copies are committed on purpose: a fresh clone must build and test with **no generation step**.
Generating the bundled copy at build time is what makes a clone build cleanly and then throw the first
time `rootBundle.loadString` is called.

## Keeping them in sync

```sh
cp schema/*.json assets/schema/     # from the repo root
```

If you change the contract, change the root `schema/` files, run the copy above, and commit both.
`test/schema_parity_test.dart` fails if the two ever diverge — the app loads the bundled copy while
the docs render their column tables from the root one, so a silent mismatch would publish a reference
describing a contract the app does not implement.
