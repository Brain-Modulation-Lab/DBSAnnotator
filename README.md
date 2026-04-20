# DBS Annotator

[![CI](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/ci.yml/badge.svg)](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/ci.yml)
[![Docs Health](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/docs-health.yml/badge.svg)](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/docs-health.yml)
[![Release Drafter](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/release-drafter.yml/badge.svg)](https://github.com/Brain-Modulation-Lab/App_ClinicalDBSAnnot/actions/workflows/release-drafter.yml)

A desktop application for annotating Deep Brain Stimulation (DBS) clinical programming sessions. Built for clinicians and researchers working with DBS systems (Medtronic Percept and others).

**Version:** derived from `dbs_annotator.__version__`
**Publisher:** Wyss Center (contact: lucia.poma@wysscenter.ch)

## For End Users

Releases ship as **Briefcase-generated** artifacts (for example ZIP/MSI on Windows and DMG on macOS). Follow the instructions for the artifact you downloaded.

## What It Does

The application guides you through a DBS programming session in three steps:

1. **Initial Setup** — Select output file, electrode model, initial stimulation parameters, and baseline clinical scales
2. **Session Scales** — Choose which scales to track during the session (Mood, Anxiety, Energy, etc.)
3. **Active Recording** — Adjust stimulation parameters in real-time, record scale values at each timepoint, add notes, and export a clinical report

There is also a **Free Annotations** mode for quick timestamped text annotations without the full stimulation workflow.

### Key Features

- **Electrode visualization** with interactive contact selection (supports directional leads)
- **Clinical scale presets** for OCD, MDD, PD, ET
- **BIDS-compliant file naming** (sub-XX_ses-YYYYMMDD_task-programming_run-XX_events.tsv)
- **Export to Word** with electrode configuration images, clinical notes, and session data tables
- **Dark/Light theme** toggle
- **Timestamps aligned** with Medtronic Percept data (Eastern Time)

### Output Format

Data is saved as TSV. The canonical schema is documented in
[`docs/output_format.rst`](docs/output_format.rst) and auto-generated from the
code-level constants in `dbs_annotator.config` to prevent drift.

## Contributing

We welcome contributions! Please see the [Contributing Guide](CONTRIBUTING.md) for detailed guidelines on:

- Bug reports and feature requests
- Code contributions and pull requests
- Development setup and testing
- Community guidelines

### Quick Contribution Steps

1. Fork the repository
2. Create a feature branch
3. Make your changes following PEP 8
4. Add tests for new functionality
5. Submit a pull request

## For Developers

### Prerequisites

- Python 3.12+ (see `requires-python` in `pyproject.toml`)
- [uv](https://github.com/astral-sh/uv) (recommended) or pip

### Setup

```bash
cd App_ClinicalDBSAnnot

# With uv (recommended)
uv sync

# Install git hooks (pre-commit runs with pre-commit-uv from dev dependencies)
uv run pre-commit install

# Or with pip
pip install -e .
```

### Running from Source

```bash
python -m dbs_annotator
# or, once the project is installed, the console script
dbs-annotator
```

### Project Structure

```
App_ClinicalDBSAnnot/
├── src/dbs_annotator/   # Application source code
│   ├── models/                   #   Data models (session, scales, stimulation, electrode)
│   ├── views/                    #   Qt views (step0-3, annotations, wizard window)
│   ├── controllers/              #   Business logic (wizard controller)
│   ├── ui/                       #   Reusable UI widgets and dialogs
│   ├── utils/                    #   Utilities (export, themes, responsive, resources)
│   ├── config.py                 #   App configuration and constants
│   └── config_electrode_models.py #  Electrode model definitions
├── styles/                       # QSS theme files (Briefcase + dev; see resource_path)
├── icons/                        # Application icons
├── scripts/                      # Utility scripts
└── pyproject.toml                # Project configuration and dependencies
```

Architecture follows the **Model-View-Controller (MVC)** pattern.

### Native installers (BeeWare Briefcase)

Briefcase turns this repo into **platform-native** bundles and installers. The GUI stack is **PySide6** (Qt); the packaged entrypoint is `python -m dbs_annotator` via `src/dbs_annotator/__main__.py`.

**Install tooling (once per machine):**

- **Windows:** [WiX Toolset](https://wixtoolset.org/) is required only if you build **MSI** installers (`briefcase package windows` defaults to MSI). For CI and quick artifacts, use **ZIP** packaging instead (no WiX): `briefcase package windows -p zip`.
- **macOS:** Xcode **Command Line Tools** (`xcode-select --install`). For **DMG** output, Briefcase pulls `dmgbuild` via dependencies.

**Typical local flow:**

```bash
uv sync --locked --dev --group build
uv export --locked --format requirements.txt --no-dev --no-hashes --no-emit-project --no-emit-workspace --output-file constraints-briefcase.txt

# First-time / after config changes — pick platform + format (examples):
uv run briefcase create macOS app
uv run briefcase build macOS app
uv run briefcase package macOS -p dmg

uv run briefcase create windows app
uv run briefcase build windows app
uv run briefcase package windows -p zip    # avoids WiX; omit -p (MSI) when WiX is installed
```

`macOS` builds on Apple Silicon produce **arm64** artifacts when `universal_build = false` is set under `[tool.briefcase.app.dbs_annotator.macOS]` in `pyproject.toml`.

**Windows Briefcase quirks:** keep `[tool.briefcase].version` in sync with `dbs_annotator.__version__` (Briefcase does not use Hatch’s dynamic `[project]` version). If `briefcase build` fails at **“Setting stub app details”** / RCEdit with **“Unable to commit changes”**, exclude the repo or `build\` from real-time antivirus scanning and retry (see [Briefcase issue #1530](https://github.com/beeware/briefcase/issues/1530)).

The Windows stub binary is named **`DBSAnnotator.exe`** (from `[tool.briefcase.app.dbs_annotator].formal_name`). After changing that field, run **`briefcase create windows app`** again (or delete `build\dbs_annotator\windows`) before **`briefcase build`**.

Icons for the **stub**, **MSI/ZIP**, and **Qt** (`QApplication` / window chrome) come from **`icons/logoneutral.ico`** and **`icons/logoneutral.png`** at the **repository root** (`icon = "icons/logoneutral"` in `pyproject.toml`). That folder is also listed as a Briefcase **`sources`** entry so a sibling `icons\` directory is shipped next to the app package inside the bundle. Runtime lookup uses `resource_path()` (package dir, then `src\icons`, then repo-root `icons\`).

**Inventory (for packaging):**

| Area | Notes |
| --- | --- |
| App type | Qt **GUI** (`console_app` is false by default). |
| Heavy deps | `PySide6`, `matplotlib`, `pandas`, `python-docx`, `docx2pdf` (Windows: `pywin32`; macOS: `appscript` via `docx2pdf`). |
| Data files | JSON presets under `src/dbs_annotator/config/`; QSS and SVG under repo-root **`styles/`** (also a Briefcase **`sources`** entry); **`icons/logoneutral.{ico,png}`** at repo root (Briefcase + Qt). |
| macOS entitlements | Add an entitlements plist only if you enable the Hardened Runtime and need extra capabilities (network is usually fine without custom entitlements). |

### Release signing (distribution outside store)

Signing is **not** wired in CI by default; release engineers use local or protected-runner secrets.

**macOS (Developer ID + notarization):**

1. Sign the `.app` (and DMG/PKG if applicable) with your **Developer ID Application** identity.
2. Submit with `xcrun notarytool` (App Store Connect API key) and **staple** the ticket with `xcrun stapler staple`.
3. Apple’s overview: [Developer ID](https://developers.apple.com/developer-id), [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

**Windows (Authenticode):**

1. Sign the installer and/or binaries with **signtool** and your code-signing certificate (EV certificates accumulate **SmartScreen** reputation faster than OV-only setups).
2. Briefcase documents Windows signing flags (`--cert-store`, `--timestamp-url`, etc.) in the [Windows platform reference](https://briefcase.beeware.org/en/latest/reference/platforms/windows/).

**GitHub Actions secrets (when you automate signing):**

| Secret | Purpose |
| --- | --- |
| `WINDOWS_SIGN_PFX_BASE64` | Base64-encoded PFX certificate used by `signtool` in `release.yml` |
| `WINDOWS_SIGN_PFX_PASSWORD` | Password for the PFX above |
| `APPLE_IDENTITY` | Developer ID identity name for `codesign` |
| `APPLE_API_ISSUER` | App Store Connect issuer for `notarytool` |
| `APPLE_API_KEY_ID` | App Store Connect key id for `notarytool` |
| `APPLE_API_KEY` | Contents of the `.p8` key file (stored as secret text) |

**Test release workflow before tagging:**

1. Open Actions and run `CD - Create GitHub Release` manually (`workflow_dispatch`).
2. Set `publish_release=false` to build and upload artifacts **without** creating a release.
3. Optionally set `sign_artifacts=true` to validate signing gates; leave it `false` if secrets are not configured yet.

### Running Tests

```bash
pytest
```

### Dependency security and updates (uv)

This project uses `uv` for dependency locking, security auditing, and update automation.

- **Audit vulnerabilities locally:** `uv audit`
- **Upgrade all locked dependencies:** `uv lock --upgrade`
- **Upgrade one dependency:** `uv lock --upgrade-package <package>`
- **Re-sync after lock changes:** `uv sync --locked --dev --group build`

To reduce supply-chain risk from very new releases, dependency resolution is configured with:

- `pyproject.toml` -> `[tool.uv] exclude-newer = "1 week"`

In CI/automation:

- `CI - Lint and Type Check` runs `uv audit` on each push/PR.
- Dependabot updates the `uv.lock` ecosystem weekly with a 7-day cooldown before opening update PRs.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contact

Wyss Center — lucia.poma@wysscenter.ch