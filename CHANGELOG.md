# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
