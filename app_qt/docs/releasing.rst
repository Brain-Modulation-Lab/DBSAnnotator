Releasing
=========

This project uses a **pull request** to prepare each release, then a **manual Git tag**
as the only step that starts publication (GitHub Actions builds installers and
creates a GitHub Release when a ``v*`` tag is pushed).

Version sources
---------------

Keep these in sync whenever you cut a release:

- ``__version__`` in ``src/dbs_annotator/__init__.py`` — Hatch reads this as the
  ``dbs-annotator`` distribution version (PEP 440: stable ``X.Y.Z`` or prereleases
  such as ``X.Y.Za1``, ``X.Y.Zb2``, ``X.Y.Zrc1``).
- ``version`` under ``[tool.briefcase]`` in ``pyproject.toml`` (Briefcase requires a static string)

The automation below updates both, then runs `Towncrier`_ to fold Markdown fragments
under ``newsfragments/`` into ``CHANGELOG.md`` (see ``[tool.towncrier]`` in
``pyproject.toml``).

.. _Towncrier: https://towncrier.readthedocs.io/

Day-to-day: changelog fragments
-------------------------------

.. _Keep a Changelog: https://keepachangelog.com/en/1.1.0/

For each PR that should appear in the release notes, add a fragment in ``newsfragments/``
(usually in the same PR as the change). Types match *Types of changes* in
`Keep a Changelog`_: ``added``, ``changed``, ``deprecated``, ``removed``, ``fixed``,
``security`` (for example ``123.added.md`` or ``123.changed.md`` for PR number 123).

Create a stub interactively:

.. code-block:: bash

   uv run towncrier create 123.added.md

CI may require a fragment when certain paths change unless the PR is labeled
``skip-changelog`` or ``internal-only`` (see ``CONTRIBUTING.md``).

Option A — Prepare the release PR locally
-----------------------------------------

1. Ensure ``main`` is up to date and you have a **clean** working tree (or pass
   ``--allow-dirty`` only if you intend to include other edits — not recommended).

2. Create a branch (do **not** commit the release bump directly on ``main``):

   .. code-block:: bash

      git checkout main
      git pull
      git checkout -b chore/release-prep-X.Y.Z

3. Run the helper (omit ``--commit`` first if you want to inspect diffs only):

   .. code-block:: bash

      uv sync --dev
      uv run python scripts/release_prepare.py 0.4.0 --dry-run
      uv run python scripts/release_prepare.py 0.4.0rc1 --commit

   Instead of typing the next version explicitly, derive it from the current
   ``__version__`` with ``--bump``:

   .. code-block:: bash

      uv run python scripts/release_prepare.py --bump alpha --dry-run
      uv run python scripts/release_prepare.py --bump beta --dry-run
      uv run python scripts/release_prepare.py --bump rc --dry-run
      uv run python scripts/release_prepare.py --bump stable --dry-run
      uv run python scripts/release_prepare.py --bump patch --dry-run

   ``alpha`` / ``beta`` / ``rc`` advance the prerelease train; ``stable`` drops
   prerelease labels (``0.4.0rc2`` → ``0.4.0``). ``patch`` / ``minor`` / ``major``
   apply only when there is **no** prerelease segment (run ``--bump stable`` first).

   Use ``--date YYYY-MM-DD`` if the Towncrier release date should not be “today”.
   Use ``--skip-towncrier`` only in exceptional cases (changelog skipped).

4. Push the branch and open a pull request into ``main``. Wait for CI to pass, then
   merge.

Option B — Prepare the release PR from GitHub Actions
-------------------------------------------------------

1. In GitHub: **Actions** → **CD - Prepare release PR** → **Run workflow**.

2. Enter **Version** (PEP 440 string without a ``v`` prefix, e.g. ``0.4.0`` or
   ``0.4.0a1``). Optionally set **Release date** (``YYYY-MM-DD``); otherwise UTC
   “today” is used.

3. The workflow creates branch ``chore/release-prep-X.Y.Z``, runs the same steps as
   ``scripts/release_prepare.py``, pushes it, and opens a pull request.

4. Review and merge the PR when CI is green.

Publish: tag after merge (deliberate final step)
------------------------------------------------

After the release-prep PR is **merged** into ``main``:

1. Update your local ``main`` and identify the **merge commit** (or use GitHub’s
   suggested SHA for the PR merge).

2. Create an **annotated** tag matching the version (``v`` prefix for the git tag
   only):

   .. code-block:: bash

      git checkout main
      git pull
      git tag -a vX.Y.Z -m "Release vX.Y.Z" <merge_commit_sha>
      git push origin vX.Y.Z

   If ``origin`` is your **fork**, use ``git push upstream vX.Y.Z`` to the
   canonical lab repository (see the next section); ``git push origin`` alone is not
   enough to run CD there.

3. That push triggers ``.github/workflows/release.yml`` (tag pattern ``v*``), which
   builds Python wheels and Briefcase artifacts and, when appropriate, publishes a
   GitHub Release.

Publish when ``origin`` is a fork
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you usually clone from your **fork** and ``git pull`` from ``main`` on the
**canonical** repository, your remotes are typically:

- ``origin`` — your fork (``git@github.com:<you>/<fork>.git``)
- ``upstream`` — the lab repository where releases and ``main`` live

In that case, ``git push origin vX.Y.Z`` only puts the tag on your fork. **GitHub
Actions runs in the repository that receives the tag push.** Pushing the tag only
to the fork will **not** run the org’s CD pipeline or create the release in the
canonical project, even if you have **push access** to the upstream remote.

**After** you create the same annotated tag on the merge commit in your local
``main`` (which should match ``upstream/main`` or be fast-forwarded to it), **push
the tag to the upstream remote**:

.. code-block:: bash

   # Once per machine: add upstream if missing
   # git remote add upstream git@github.com:Brain-Modulation-Lab/DBSAnnotator.git
   git fetch upstream
   git checkout main
   git pull upstream main
   git tag -a vX.Y.Z -m "Release vX.Y.Z" <merge_commit_sha>   # only if you have not already
   git push upstream vX.Y.Z

You can also ``git push origin vX.Y.Z`` so your fork has the same tag, but the
**upstream** push is the one that must happen for the official CD release. Verify
remotes with ``git remote -v`` if you are unsure.

Do **not** push a ``v*`` tag until the release-prep PR is merged and you are satisfied
with ``CHANGELOG.md`` and the version numbers on ``main``.

Manual workflow dispatch on ``release.yml`` can still build artifacts without a new
tag; see that workflow’s inputs if you need a one-off build.

Troubleshooting
---------------

- **“Working tree is not clean”** — stash or commit unrelated work, or use a fresh clone.
- **Towncrier fails** — ensure there is at least one valid fragment for the release, or
  confirm ``CHANGELOG.md`` still contains the ``## [Unreleased]`` heading Towncrier
  uses as ``start_string`` in ``pyproject.toml``.
- **Branch already exists** — delete the remote branch ``chore/release-prep-X.Y.Z`` or
  pick a new branch name before re-running the workflow.
