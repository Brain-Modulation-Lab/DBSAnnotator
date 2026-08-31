# Bundled schema contract

These four JSON files are the machine-readable domain contract — TSV columns, BIDS filename format,
stimulation limits and presets, electrode-model geometry — and they are **tracked in git**.

They are a bundled copy. The canonical copy is the repo-root `schema/`, because Flutter can only bundle
assets that live under the project directory, so the app needs its own copy under `assets/`.

Both copies are committed on purpose: a fresh clone must build and test with **no generation step**.
They used to be gitignored and produced by `cp ../schema/*.json assets/schema/` in six CI steps, which
meant a clone built fine and then threw at runtime the first time `rootBundle.loadString` was called.

## Keeping them in sync

```sh
cp schema/*.json assets/schema/     # from the repo root
```

If you change the contract, change the root `schema/` files, run the copy above, and commit both.
The two must never diverge: runtime reads the bundled copy while several tests read the root one, so
a mismatch shows up as "works in tests, wrong in the app".
