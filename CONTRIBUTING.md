# Contributing to Clinical DBS Annotator

We welcome contributions to the Clinical DBS Annotator! This document provides guidelines for contributors who want to help improve this open-source software for deep brain stimulation research.

For detailed guidelines, please see the [Contributing Guide](docs/contributing.rst).

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

## Getting Help

- Check existing issues and discussions
- Read the [documentation](docs/)
- Ask questions in GitHub Discussions

Thank you for contributing!
