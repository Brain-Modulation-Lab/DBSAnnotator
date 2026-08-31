# Towncrier fragments

This project uses [Towncrier](https://towncrier.readthedocs.io/) to build
`CHANGELOG.md` from per-PR fragments, using the
[Types of changes](https://keepachangelog.com/en/1.1.0/) from *Keep a Changelog* 1.1.0:
**Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## How to add an entry

For a PR number `123`, add exactly one fragment file (choose the type that matches the
change; documentation-only updates usually use `changed`):

- `newsfragments/123.added.md`
- `newsfragments/123.changed.md`
- `newsfragments/123.deprecated.md`
- `newsfragments/123.removed.md`
- `newsfragments/123.fixed.md`
- `newsfragments/123.security.md`

The file content should be one short bullet-ready sentence, for example:

`Fix memory leak in session export for empty scales.`

**Filename rules (enforced in CI):** `newsfragments/<id>.<type>.md` where `id` is
the issue/PR number and `type` is one of the six names above. On pull requests, any
changed fragment in the diff must use **this** PR’s number as `id` (e.g. PR 66 →
`66.changed.md`). See `scripts/validate_newsfragments.py`.

## When a fragment is not needed

Maintainers may apply the `skip-changelog` or `internal-only` label to bypass
fragment requirements for internal-only changes.
