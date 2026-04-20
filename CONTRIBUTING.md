# Contributing to DBS Annotator

We welcome contributions to DBS Annotator! This document provides guidelines for contributors who want to help improve this open-source software for deep brain stimulation research.

For detailed guidelines, please see the [Contributing Guide](docs/contributing.rst).

**Releases (maintainers):** use the PR-based process and manual `v*` tag described in [docs/releasing.rst](docs/releasing.rst) (Sphinx: *Developer guide → Releasing*). The helper is `scripts/release_prepare.py`; GitHub Actions workflow **CD - Prepare release PR** runs the same steps.

## Quick Start

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Install pre-commit hooks: `uv run pre-commit install`
4. Make your changes following our coding standards
5. Add tests for new functionality
6. Submit a pull request

## Key Requirements

- Follow PEP 8 style guidelines
- Include tests for new features
- Update documentation when needed
- Ensure all tests pass before submitting
- If you change build-time dependencies in `pyproject.toml` (including the **`build`** group used by Briefcase), run **`uv lock`** and commit the updated **`uv.lock`**

## Changelog Fragments (Towncrier)

We use Towncrier for changelog automation.

- Add one fragment per PR in `newsfragments/`:
  - `newsfragments/<PR>.added.md`
  - `newsfragments/<PR>.changed.md`
  - `newsfragments/<PR>.fixed.md`
  - `newsfragments/<PR>.docs.md`
- Use one short sentence suitable for changelog bullet points.
- PRs without a fragment may fail CI unless explicitly labeled `skip-changelog` or `internal-only`.

## Getting Help

- Check existing issues and discussions
- Read the [documentation](docs/)
- Ask questions in GitHub Discussions

Thank you for contributing!
