# Towncrier fragments

This project uses [Towncrier](https://towncrier.readthedocs.io/) to build
`CHANGELOG.md` from per-PR fragments.

## How to add an entry

For a PR number `123`, add exactly one fragment file:

- `newsfragments/123.added.md`
- `newsfragments/123.changed.md`
- `newsfragments/123.fixed.md`
- `newsfragments/123.docs.md`

The file content should be one short bullet-ready sentence, for example:

`Improve docs build reproducibility by generating schema tables from code constants.`

## When a fragment is not needed

Maintainers may apply the `skip-changelog` or `internal-only` label to bypass
fragment requirements for internal-only changes.
