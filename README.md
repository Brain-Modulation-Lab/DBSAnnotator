# DBS Annotator

[CI](https://github.com/Brain-Modulation-Lab/DBSAnnotator/actions/workflows/ci.yml)
[Docs Health](https://github.com/Brain-Modulation-Lab/DBSAnnotator/actions/workflows/docs-health.yml)
[Release Drafter](https://github.com/Brain-Modulation-Lab/DBSAnnotator/actions/workflows/release-drafter.yml)

A desktop application for annotating Deep Brain Stimulation (DBS) programming sessions. Built for clinicians and researchers working with DBS systems.

**Publisher:** Wyss Center for Bio and Neuroengineering (contact: [lucia.poma@wysscenter.ch](mailto:lucia.poma@wysscenter.ch))

## For End Users

You can find installation files for Windows (.msi), MacOS (.dmg) and Linux (.deb) under the [GitHub Releases](https://github.com/Brain-Modulation-Lab/DBSAnnotator/releases).
However, note that the files are unsigned, so that a warning might pop up during installation. To proceed with installation, you must accept the risk and continue.
In some cases, for example where your organization has strict settings, this might not be possible. In this case, try the install via PowerShell below.

### Windows — install via PowerShell

In an **open PowerShell** window:

```powershell
irm https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.ps1 | iex
```

From **cmd.exe** (or if execution policy blocks scripts):

```bat
powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.ps1 | iex"
```

### macOS / Linux — shell install (curl / wget)

```sh
curl -LsSf https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.sh | sh
```

```sh
wget -qO- https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.sh | sh
```

## What It Does

From the home screen you can start three workflows (full guide:
[Read the Docs](https://brain-modulation-lab.github.io/DBSAnnotator/)):

### Complete Workflow

Four steps — stimulation parameters, clinical scales, session scales, and notes;
data saved automatically after each entry:

1. **Step 0 — File setup** — Open or create a programming-session TSV
  (`sub-XX_ses-YYYYMMDD_task-programming_run-XX_events.tsv`); **New** asks for
   Patient ID and Run ID (Session ID is today's date).
2. **Step 1 — Initial Configuration** — Electrode model, baseline stimulation
  parameters, and clinical scales.
3. **Step 2 — Session Scale Selection** — Scales rated at each configuration
  during programming (e.g. Tremor, Mood).
4. **Step 3 — Active Recording** — Adjust parameters, rate scales, add notes;
  click **Insert** to record an entry; export a Word/PDF report when finished.

See `[docs/workflow_complete.rst](docs/workflow_complete.rst)` for the full
step-by-step guide (screenshots, scale presets, report sections, and videos).

### Annotations-only Workflow

Timestamped text notes only — no stimulation parameters or scale values.  Uses a
dedicated TSV (`task-notes`) with columns `date`, `time`, `timezone`, and
`annotation`.  See `[docs/workflow_annotations.rst](docs/workflow_annotations.rst)`.

### Create Longitudinal Report

Combine multiple programming-session TSV files from the same subject into one
comparative Word/PDF report.  See `[docs/longitudinal_report.rst](docs/longitudinal_report.rst)`.

### Key Features

- **Clinical and session scale presets** for OCD, MDD, PD, ET, Dystonia, TS
- **Timestamps aligned** notes, configuration parameters and scale scores
- **Export to Word / PDF** with electrode diagrams, tables, and timeline charts
- **BIDS-compliant file naming** for programming and annotations TSV files
- **Electrode visualization** with interactive contact selection (supports directional leads)
- **Dark/Light theme** toggle

### Output Format

Programming and annotations data are saved as TSV. The canonical schema is
documented in `[docs/output_format.rst](docs/output_format.rst)` and
auto-generated from `dbs_annotator.config` to prevent drift.

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
cd DBSAnnotator

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
DBSAnnotator/
├── src/dbs_annotator/   # Application source code
│   ├── models/                   #   Data models (session, scales, stimulation, electrode)
│   ├── views/                    #   Qt views (step0-3, annotations, wizard window)
│   ├── controllers/              #   Business logic (wizard controller)
│   ├── ui/                       #   Reusable UI widgets and dialogs
│   ├── utils/                    #   Utilities (export, themes, responsive, resources)
│   ├── config.py                 #   App configuration and constants
│   └── config_electrode_models.py #  Electrode model definitions
├── styles/                       # QSS theme files (Briefcase + dev; see resource_path)
├── icons/                        # Application icons (e.g. logosimple/ bundle)
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

**Windows Briefcase quirks:** keep `[tool.briefcase].version` in sync with `dbs_annotator.__version__` (Briefcase does not use Hatch’s dynamic `[project]` version). Bump both in one step with `uv run python scripts/release_prepare.py <version>` (or `--bump …`). If `briefcase build` fails at **“Setting stub app details”** / RCEdit with **“Unable to commit changes”**, exclude the repo or `build\` from real-time antivirus scanning and retry (see [Briefcase issue #1530](https://github.com/beeware/briefcase/issues/1530)).

The Windows stub binary is named `**DBSAnnotator.exe`** (from `[tool.briefcase.app.dbs_annotator].formal_name`). After changing that field, run `**briefcase create windows app`** again (or delete `build\dbs_annotator\windows`) before `**briefcase build**`.

Icons for the **stub**, **MSI/ZIP**, and **Qt** (`QApplication` / window chrome) live under `**icons/logosimple/`**: `**logosimple.ico`**, `**logosimple.png**`, plus `**logosimple-{16,32,64,128,256,512}.png**` for Linux system (BeeWare copies them into the Freedesktop hicolor tree; all six are listed in the upstream `briefcase-linux-system-template`). `**logosimple.icns**` is for macOS (build with `iconutil` on a Mac; see `scripts/build_app_icons.py`). Configure with `icon = "icons/logosimple/logosimple"` in `pyproject.toml`. The repo-root `**icons/**` tree is a Briefcase `**sources**` entry and is shipped next to the app package; runtime lookup uses `resource_path()` (package dir, then `src/icons`, then repo-root `icons/`).

**Inventory (for packaging):**


| Area               | Notes                                                                                                                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App type           | Qt **GUI** (`console_app` is false by default).                                                                                                                                             |
| Heavy deps         | `PySide6`, `matplotlib`, `pandas`, `python-docx`, `docx2pdf` (Windows: `pywin32`; macOS: `appscript` via `docx2pdf`).                                                                       |
| Data files         | JSON presets under `src/dbs_annotator/config/`; QSS and SVG under repo-root `**styles/`** (also a Briefcase `**sources`** entry); app icons under `**icons/logosimple/**` (Briefcase + Qt). |
| macOS entitlements | Add an entitlements plist only if you enable the Hardened Runtime and need extra capabilities (network is usually fine without custom entitlements).                                        |


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


| Secret                      | Purpose                                                            |
| --------------------------- | ------------------------------------------------------------------ |
| `WINDOWS_SIGN_PFX_BASE64`   | Base64-encoded PFX certificate used by `signtool` in `release.yml` |
| `WINDOWS_SIGN_PFX_PASSWORD` | Password for the PFX above                                         |
| `APPLE_IDENTITY`            | Developer ID identity name for `codesign`                          |
| `APPLE_API_ISSUER`          | App Store Connect issuer for `notarytool`                          |
| `APPLE_API_KEY_ID`          | App Store Connect key id for `notarytool`                          |
| `APPLE_API_KEY`             | Contents of the `.p8` key file (stored as secret text)             |


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

Wyss Center for Bio and Neuroengineering — [lucia.poma@wysscenter.ch](mailto:lucia.poma@wysscenter.ch)