# Before submitting to JOSS

Everything here needs a decision or a fact that is not in the repository. Delete this
file once the paper is submitted.

## 1. Authorship

JOSS requires that every author made a substantial contribution to the *software*.
The repository records these names, but a record is not an author list:

- **Lucia Poma** - lead author and developer (`lib/app_info.dart`).
- **Richard Koehler** - recorded as maintainer in the project's earlier documentation.
  Confirm whether this is an authorship contribution.
- The copyright line names three institutions: the Wyss Center for Bio and
  Neuroengineering, Massachusetts General Hospital, and Charite Universitaetsmedizin
  Berlin. Institutions are affiliations, not authors - decide who from each, if anyone,
  should appear.

`paper/paper.md` currently lists one author, one affiliation, and a placeholder ORCID
(`0000-0000-0000-0000`). Every author needs a real ORCID and a numbered affiliation.
`CITATION.cff` carries the same single author and a commented-out ORCID line; keep the
two files consistent.

## 2. The statement of need needs citations

The argument in `paper.md` is built from the software's own design decisions and is
accurate, but it cites only the BIDS paper. An uncited claim about clinical practice is
the most likely thing a reviewer challenges. `paper/paper.bib` lists what is missing.

Also worth adding, and impossible to write from the code: **evidence of real use** -
which sites, how many sessions, over what period. A tool with demonstrated clinical use
is a substantially stronger submission.

## 3. Release artefacts JOSS will not proceed without

- A **tagged release** and an **archive with a DOI**. Zenodo links to GitHub releases
  directly and is the usual route.
- Then set `version`, `date-released` and `doi` in `CITATION.cff`, which currently has
  TODO comments for the last two.

## 4. Check before making it permanently public

- The example session under `test/fixtures/` is used throughout the documentation and
  the paper's worked example. Confirm it is de-identified to your institution's
  satisfaction.
- `paper.md` makes no test-count claim, deliberately - the README's number will drift.
  If you add one at submission time, re-run `flutter test` and use the real figure.
