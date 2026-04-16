# Clinical DBS Annotator

A desktop application for annotating Deep Brain Stimulation (DBS) clinical programming sessions. Built for clinicians and researchers working with DBS systems (Medtronic Percept and others).

**Version:** derived from `dbs_annotator.__version__`
**Author:** Lucia Poma (lucia.poma@wysscenter.ch)

## For End Users

**No installation required.** Download the pre-built executable and run it directly:

1. Go to the `dist/` folder
2. Run the `ClinicalDBSAnnotator_*.exe` artifact for your platform/version
3. That's it — the application opens immediately

The executable is self-contained and includes all dependencies.

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

Data is saved as TSV with columns: `date`, `time`, `block_id`, `is_initial`, `session_ID`, `electrode_model`, `scale_name`, `scale_value`, stimulation parameters (frequency, contacts, amplitude, pulse width per side), `group`, and `notes`.

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

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (recommended) or pip

### Setup

```bash
cd App_ClinicalDBSAnnot

# With uv (recommended)
uv sync

# Or with pip
pip install -e .
```

### Running from Source

```bash
python run.py
# or
python -m dbs_annotator
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
├── styles/                       # QSS theme files (dark/light)
├── icons/                        # Application icons
├── scripts/                      # Build scripts (Windows, macOS)
├── run.py                        # Development entry point
└── pyproject.toml                # Project configuration and dependencies
```

Architecture follows the **Model-View-Controller (MVC)** pattern.

### Building the Executable

```bash
# Windows
python scripts/build_windows.py

# Windows with console (for debugging)
python scripts/build_windows.py --console

# macOS
python scripts/build_macos.py
```

The executable is created in the `dist/` folder. Distribute this file — no Python installation needed on the target machine.

### Running Tests

```bash
pytest
```

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contact

Lucia Poma — lucia.poma@wysscenter.ch