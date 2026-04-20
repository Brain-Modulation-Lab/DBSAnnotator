Contributing to DBS Annotator
======================================

We welcome contributions to DBS Annotator! This page is the authoritative
contributor guide for the repository. The short ``CONTRIBUTING.md`` at the
repository root is a pointer into this page.

.. contents::
   :local:
   :depth: 2

Getting Started
---------------

Prerequisites
~~~~~~~~~~~~~

To contribute to this project, you should have:

- **Python 3.12 or newer** (matches ``requires-python`` in ``pyproject.toml``;
  CI uses 3.12 on Ubuntu, Windows, and macOS).
- **uv** (https://github.com/astral-sh/uv) for dependency management and
  running tools.
- **Git** installed and configured.
- Familiarity with **PySide6 / Qt** is helpful but not required. The codebase
  follows a Model-View-Controller (MVC) structure under ``src/dbs_annotator/``.
- Understanding of deep brain stimulation concepts is helpful for clinical
  contributions but not required for code or documentation work.

Development Setup
~~~~~~~~~~~~~~~~~

1. **Fork the repository** on GitHub and clone your fork:

   .. code-block:: bash

      git clone https://github.com/<your-username>/App_ClinicalDBSAnnot.git
      cd App_ClinicalDBSAnnot

2. **Create the virtual environment and install all dev dependencies**
   (``uv`` reads ``pyproject.toml`` and ``uv.lock``; no manual ``venv``
   activation is needed):

   .. code-block:: bash

      uv sync --locked --dev

   To additionally install the Briefcase packaging tools, use the ``build``
   group:

   .. code-block:: bash

      uv sync --locked --dev --group build

   To build the documentation locally, use the ``docs`` group:

   .. code-block:: bash

      uv sync --locked --group docs --no-dev

3. **Install the git pre-commit hooks** (ruff, ty, actionlint, ``uv lock``
   check):

   .. code-block:: bash

      uv run pre-commit install

4. **Run the application** to verify the installation:

   .. code-block:: bash

      uv run python -m dbs_annotator
      # or, once installed, the console script declared in pyproject.toml
      uv run dbs-annotator

Types of Contributions
----------------------

We welcome the following types of contributions:

Bug Reports
~~~~~~~~~~~

If you find a bug, please:

1. **Check existing issues** to see if it's already reported.
2. **Create a new issue** with:

   - Clear title describing the bug.
   - Steps to reproduce the issue.
   - Expected vs actual behaviour.
   - System information (OS, Python version, application version from
     ``dbs_annotator.__version__``).
   - Screenshots or a short screen recording if the issue is in the GUI.

Feature Requests
~~~~~~~~~~~~~~~~

For new features:

1. **Check existing issues** for similar requests.
2. **Open an issue** describing:

   - The feature you'd like to see.
   - Why it would be useful (clinical motivation, research workflow, etc.).
   - How you envision it working.
   - Any implementation ideas you have.

Code Contributions
~~~~~~~~~~~~~~~~~~

We accept code contributions through pull requests. Please follow these
guidelines:

1. **Create a feature branch** off ``main`` (or the currently active
   integration branch):

   .. code-block:: bash

      git checkout -b feature/your-feature-name

2. **Make your changes** following the coding standards below.

3. **Run the local quality gate** before pushing:

   .. code-block:: bash

      uv run ruff format .
      uv run ruff check .
      uv run ty check .
      uv run pytest

4. **Commit your changes** using a short, descriptive message (Conventional
   Commits are encouraged but not required):

   .. code-block:: bash

      git commit -m "feat: add directional-lead contact picker"

5. **Push to your fork** and open a pull request against the upstream
   repository.

Documentation Improvements
~~~~~~~~~~~~~~~~~~~~~~~~~~

Documentation lives in this ``docs/`` tree (Sphinx + reStructuredText) plus
``README.md`` and ``CHANGELOG.md`` at the repository root. We welcome:

- New or revised user-workflow pages.
- API docstring improvements (Google or NumPy style; rendered by
  ``sphinx.ext.napoleon``).
- Additional examples, screenshots, or short screencasts.
- Fixing typos and grammatical errors.

Build the docs locally before submitting:

.. code-block:: bash

   uv sync --locked --group docs --no-dev
   uv run sphinx-build -b html -W --keep-going docs docs/_build/html
   uv run sphinx-build -b linkcheck docs docs/_build/linkcheck

Optional: regenerate UI screenshot artifacts for docs (uploaded as CI artifact):

.. code-block:: bash

   QT_QPA_PLATFORM=offscreen DOCS_SCREENSHOT_DIR=docs/_build/screenshots \
     uv run pytest tests/docs/test_docs_screenshots.py -m docs_screenshot

Sphinx-related paths under ``docs/``:

- **``docs/_static/``** — **Keep in version control.** These are source assets (images,
  optional extra CSS/JS). Sphinx only *copies* them into ``docs/_build/html/_static/``
  when you build; the underscore is a Sphinx convention for “static inputs”, not
  garbage output.

- **``docs/_templates/``** (including ``_templates/autosummary/`` if present) —
  **Keep in version control** when the ``.html``/``.rst`` files there are **hand-written**
  Jinja templates that customize the HTML builder or autosummary. They are part of
  your documentation *source*, not generated API stubs.

- **``docs/_autosummary/``** at the **project root** (next to your ``.rst`` sources) —
  **Do not commit.** Those files are **generated stubs** produced by
  ``sphinx.ext.autosummary``; they belong in ``.gitignore`` and are recreated by
  ``sphinx-build`` (or your docs CI job).

- **``docs/_generated/``** — **Depends on your workflow.** If that directory holds
  output from a **script** (for example includes generated from Python constants),
  you can either (a) **commit** the files so a plain ``sphinx-build`` works everywhere,
  with CI checking they are up to date, or (b) **gitignore** them and always run the
  generator before Sphinx in CI and locally. Do **not** delete the folder if you still
  ``.. include::`` it from an ``.rst`` file unless you switch fully to (b) and teach
  CI to regenerate it.

**Never commit** the HTML tree ``docs/_build/`` (already ignored).

Code Standards
---------------

Style Guidelines
~~~~~~~~~~~~~~~~

Formatting and linting are enforced by **ruff** (see ``[tool.ruff]`` in
``pyproject.toml``) and static typing is checked by **ty**. Both run in CI and
as pre-commit hooks, so local runs should stay green.

- **Formatter**: ``ruff format`` (line length 88).
- **Linter**: ``ruff check`` with rules ``E, W, F, I, N, UP, B, C4``.
- **Type checker**: ``ty check .``.
- **Docstrings**: Google or NumPy style (Napoleon is enabled).
- **Naming**: ``snake_case`` for functions and variables; ``PascalCase`` for
  classes; module-private names prefixed with a single underscore.

Example:

.. code-block:: python

   def calculate_total_amplitude(
       contact_states: dict[int, ContactState],
       contact_amplitudes: dict[int, float],
   ) -> float:
       """Sum the cathodic amplitude contributed by each active contact.

       Args:
           contact_states: Mapping from contact index to its active state.
           contact_amplitudes: Mapping from contact index to amplitude in mA.

       Returns:
           Total delivered cathodic amplitude in milliamps.

       Raises:
           ValueError: If ``contact_states`` is empty.
       """
       if not contact_states:
           raise ValueError("Contact states cannot be empty")

       total = 0.0
       for contact_idx, state in contact_states.items():
           if state is ContactState.CATHODIC:
               total += contact_amplitudes.get(contact_idx, 0.0)
       return total

Testing
~~~~~~~

All new features should include tests. The project uses **pytest** with
``pytest-qt`` for GUI interaction tests.

- **Unit tests** for models, utilities, and pure-logic controllers.
- **GUI tests** using ``pytest-qt`` (``qtbot`` fixture) for widget behaviour.
- **Integration tests** marked with ``@pytest.mark.integration`` for
  cross-module behaviour.
- Slow flows may be marked ``@pytest.mark.slow`` and skipped locally with
  ``pytest -m "not slow"``.

Example:

.. code-block:: python

   import pytest
   from dbs_annotator.models.electrode_viewer import ElectrodeCanvas


   @pytest.mark.gui
   def test_electrode_canvas_scales_to_widget(qtbot):
       canvas = ElectrodeCanvas()
       qtbot.addWidget(canvas)
       canvas.resize(400, 600)
       assert canvas.calculate_scale() > 0

Run tests with:

.. code-block:: bash

   uv run pytest

On headless Linux (including CI) set ``QT_QPA_PLATFORM=offscreen`` so Qt does
not require a display server:

.. code-block:: bash

   QT_QPA_PLATFORM=offscreen uv run pytest

GUI Testing
~~~~~~~~~~~

For Qt components:

1. **Test widget construction** using the ``qtbot`` fixture.
2. **Test user interactions** (clicks, key presses, text input).
3. **Test data flow** between views, controllers, and models.
4. **Test error handling** paths surfaced through the UI.

Pull Request Process
--------------------

Before Submitting
~~~~~~~~~~~~~~~~~

1. **Update documentation** in ``docs/`` when user-visible behaviour changes.
2. **Add a Towncrier fragment** under ``newsfragments/`` (for example
   ``newsfragments/<PR>.added.md`` or ``newsfragments/<PR>.fixed.md``).
   ``CHANGELOG.md`` is assembled from fragments at release time.
3. **Add or update tests** for new functionality.
4. **Run the local quality gate**: ``ruff format``, ``ruff check``,
   ``ty check``, ``pytest``.
5. **Regenerate the lockfile** if you changed dependencies in
   ``pyproject.toml`` (including the ``build`` group used by Briefcase) and
   commit the updated ``uv.lock``:

   .. code-block:: bash

      uv lock

Pull Request Template
~~~~~~~~~~~~~~~~~~~~~

When creating a pull request, please include:

**Description**

- Brief description of the change.
- Motivation (clinical workflow, bug, refactor, documentation, etc.).
- Notes on how you tested the change.

**Type of Change**

- Bug fix
- New feature
- Breaking change
- Documentation update
- Build / CI / packaging change

**Checklist**

- Code follows the project style (ruff, ty clean).
- Tests added or updated and passing locally.
- Documentation updated (``docs/`` and/or ``README.md``).
- A ``newsfragments/<PR>.(added|changed|fixed|docs).md`` entry was added,
  or the PR is explicitly labeled ``skip-changelog`` / ``internal-only``.
- ``uv.lock`` regenerated if dependencies changed.

Review Process
~~~~~~~~~~~~~~

Our review process:

1. **Automated checks** via GitHub Actions:

   - ``actionlint`` on workflow files.
   - ``uv audit`` for dependency vulnerabilities.
   - ``ruff`` (lint + format) and ``ty`` (type check).
   - ``pytest`` on Ubuntu, Windows, and macOS with a coverage floor.
   - Prose checks (codespell, doc8, interrogate) via pre-commit.
   - Briefcase smoke test on Linux (``create`` + ``build`` without packaging).
   - Documentation build (Sphinx ``-W``), TSV schema doc drift check, and link check.

2. **Peer review** by maintainers.
3. **Discussion** of any required changes.
4. **Approval** and merge.

Community Guidelines
--------------------

Code of Conduct
~~~~~~~~~~~~~~~

We are committed to providing a welcoming and inclusive environment. Please:

- Be respectful and professional.
- Welcome newcomers and help them learn.
- Focus on constructive feedback.
- Assume good intentions.
- Be patient with different perspectives.

Communication Channels
~~~~~~~~~~~~~~~~~~~~~~

- **GitHub Issues** — for bug reports and feature requests.
- **GitHub Discussions** — for general questions and ideas.
- **Pull Requests** — for code, documentation, and CI contributions.

Recognition
~~~~~~~~~~~

Contributors are recognised through:

- Author credits in the commit history.
- Acknowledgements in release notes and, where appropriate, in publications.

Research Impact
~~~~~~~~~~~~~~~

This software is designed for clinical research use. If you use or extend it
in your research:

- **Cite the software** in your publications.
- **Share feedback** so we can improve future versions.
- **Consider contributing** improvements back to the upstream repository.

Development Workflow
---------------------

Branch Strategy
~~~~~~~~~~~~~~~

We use a simple trunk-based strategy:

- ``main`` — integration branch; always releasable.
- ``feature/*`` — feature development branches.
- ``fix/*`` — bug-fix branches.
- ``docs/*`` — documentation-only branches.
- ``enh/*`` — larger enhancement / refactor branches.

Release Process
~~~~~~~~~~~~~~~

Maintainers follow a **PR-based** flow: bump versions and assemble the changelog on a
branch, merge to ``main``, then **tag** ``vX.Y.Z`` and push the tag to publish builds.

Concrete steps:

1. Update ``dbs_annotator.__version__`` in ``src/dbs_annotator/__init__.py`` (Hatch
   reads this as the distribution version) and ``[tool.briefcase].version`` in
   ``pyproject.toml``. These two values must match.
2. Build ``CHANGELOG.md`` from Towncrier fragments (or use ``scripts/release_prepare.py`` /
   the **CD - Prepare release PR** workflow), for example:

   .. code-block:: bash

      uv run towncrier build --yes --version X.Y.Z --date YYYY-MM-DD

3. Open a release PR, land it on ``main``, then push the matching ``vX.Y.Z`` tag.
4. The **CD - Create GitHub Release** workflow builds Python wheels/sdist and Briefcase
   installers (Windows MSI, macOS DMG, Linux system package), then creates the GitHub
   Release with artifacts attached.
5. Read the Docs publishes the matching versioned documentation from the tag.

See :doc:`releasing` for more detail (local script, workflow inputs, and tagging).

Continuous Integration
~~~~~~~~~~~~~~~~~~~~~~

GitHub Actions handles:

- Workflow linting (``actionlint``).
- Dependency auditing (``uv audit``).
- Lint, format, and type checking (ruff, ty).
- Cross-platform tests (Ubuntu, Windows, macOS) with coverage.
- Briefcase ZIP packaging smoke test on Windows.
- Documentation build and link check.
- Release builds for Python wheels/sdist and Briefcase installers.
- Weekly/manual docs health report artifacts (warnings and linkcheck summary).
- Manual docs screenshot artifact generation from Qt views.

Specialised Contributions
--------------------------

Clinical Domain Experts
~~~~~~~~~~~~~~~~~~~~~~~

If you are a clinician or DBS specialist:

- Share real-world session workflows and edge cases.
- Review and suggest improvements to clinical scale presets.
- Provide feedback on electrode model definitions and contact diagrams.
- Help validate clinical accuracy of exported reports.

GUI / UX Contributors
~~~~~~~~~~~~~~~~~~~~~

For contributors with design expertise:

- Improve the interaction design of the wizard steps.
- Enhance the responsive behaviour on smaller displays.
- Test accessibility (keyboard navigation, screen readers, contrast).
- Propose visual refinements to the light and dark themes.

Data Scientists
~~~~~~~~~~~~~~~

For data-science contributions:

- Improve analysis features in the longitudinal report.
- Add statistical tooling for outcome analysis.
- Enhance the BIDS-compliant TSV schema and export.
- Integrate with external analysis pipelines.

Thank You
---------

Thank you for considering contributing to DBS Annotator! Your contributions
help make deep brain stimulation research more accessible and reproducible.

For questions about contributing, please open an issue or start a discussion
on GitHub.
