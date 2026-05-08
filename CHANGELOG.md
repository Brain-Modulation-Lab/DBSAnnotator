# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
## [0.4.0b1] - 2026-05-08

### Changed

- Fixed Linux release raw-archive packaging in CI for Briefcase ``linux system`` builds by
  detecting package roots via ``usr/bin`` + ``usr/lib/dbs_annotator/app`` and archiving
  the ``usr/`` tree, ensuring the launcher is included in the uploaded raw tarball. ([#97](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/97))
## [0.4.0b0] - 2026-05-08

### Changed

- Windows install script is only `scripts/install.ps1`; removed `Install-DBSAnnotator.ps1` and updated references. ([#76](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/76))
- Persist deactivated Step 3 session scales as ``NaN`` in the session TSV and omit them from Word and PDF reports. ([#94](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/94))
- Refreshed ``uv.lock`` with upgraded dependencies (including security-related updates for
  ``pip`` and ``gitpython``). ([#95](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/95))
### Fixed

- Fix `install.ps1` when run with `iex`: move install into a nested function so `$PSCmdlet` binds; document `iex` vs script parameters (`& ([scriptblock]::Create((iwr …).Content))` or local `install.ps1`). ([#77](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/77))
- Simplify `install.ps1` and update README. ([#78](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/78))
- Fix `scripts/install.sh` for POSIX `sh` and Linux launcher paths (`bin/`, `dbs_annotator`). ([#79](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/79))
- Fix `scripts/install.sh` for POSIX `sh`, LF line endings, Linux launcher discovery (`bin/`, `dbs_annotator`), and clearer errors when a release raw `.tar.gz` lacks the Briefcase stub. Linux release workflow now selects the full `app/` tree (largest tree with `bin/`) for the raw archive. ([#80](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/80))

## [0.4.0a2] - 2026-04-22

### Added

- Add a Windows PowerShell installer (``scripts/install.ps1``) and README one-liner to install the portable release ``.zip`` from GitHub when the MSI is unsigned. ([#70](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/70))
- Add ``scripts/install.sh`` (curl/wget) to install from GitHub Releases on Linux x86_64 and macOS (raw ``.tar.gz`` when present, else ``.deb`` / ``.dmg``), with README and installation docs. ([#71](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/71))
## [0.4.0a1] - 2026-04-22

### Added

- Initial changelog scaffold following Keep a Changelog 1.1.0.

### Changed

- Deduplicate TSV schema docs by generating tables from code constants, add CI/pre-commit drift checks, and extend documentation automation with docs-touch/changelog gates, Release Drafter, and Read the Docs tag triggers. ([#51](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/51))
- Improve documentation automation and TSV schema generation. ([#52](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/52))
- Document PR-based releases (`scripts/release_prepare.py`, **CD - Prepare release PR** workflow), maintainer `docs/releasing.rst`, and Sphinx generated-dir guidance (`_autosummary`, `_generated`, `_static`, `_templates`). ([#55](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/55))
- Ship ``0.4.0a1`` alpha, space-free data/install paths (``WyssCenter`` / ``DBSAnnotator``), optional GitHub release update checks, upgrade-safe user config locations, and ``release_prepare.py --bump`` for prerelease and semver bumps. ([#62](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/62))
- Update checker compares all published GitHub releases for the highest applicable newer semver (including pre-releases), handles repos with no releases quietly, surfaces pre-release guidance with support links, and lets users turn off automatic update checks from Help or the notification. ([#63](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/63))
- Consolidate branding under `icons/logosimple/` for Briefcase and Qt, add `scripts/build_app_icons.py` to generate platform icon sizes from a single source PNG, and document Linux `linux system` icon requirements. ([#66](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/66))
