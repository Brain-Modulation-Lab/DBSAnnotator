Overview
========

DBS Annotator was developed to address recurring gaps in how deep brain
stimulation (DBS) programming sessions are documented, reviewed, and analysed
over time.  The application provides a structured, timestamped record of
each visit while remaining straightforward to use at the bedside or in the
clinic.

----

Clinical and technical context
------------------------------

During a programming session, clinicians and researchers routinely make
observations that inform contact selection, parameter titration, and
follow-up planning.  Three limitations appear frequently in routine practice:

**Untimestamped observations.**
Expert comments — for example regarding side effects, subjective improvement,
or electrode position — are clinically valuable, but lose analytical utility
when they cannot be aligned with the stimulation configuration and scale
ratings recorded at the same moment.

**Incomplete parameter logs from device software.**
Many sensing-enabled DBS systems persist stimulation parameters reliably only
when stimulation targets the central contacts used for impedance sensing.
Configurations that use the most dorsal or ventral contact, or a ring
electrode, are often tested during programming but not retained in the
device log.  Reviewing the full set of tested settings therefore requires
manual reconstruction.

**Difficulty aggregating longitudinal data.**
Tracking change in clinical scores or in-session evaluations across multiple
visits typically involves collating disparate notes, screenshots, and
spreadsheets.  Without a common format and timestamps, comparative review
and research analysis become time-consuming and error-prone.

----

What DBS Annotator provides
---------------------------

DBS Annotator offers a single desktop workflow that standardises how
programming-session information is captured and exported:

* **Guided session structure** — a step-by-step pipeline from initial
  electrode configuration through stimulation adjustments to session-specific
  ratings and notes.
* **Stimulation parameters** — frequency, amplitude, pulse width, contact
  selection, and related settings recorded for each tested configuration,
  including those not retained by device software alone.
* **Clinical scales and initial notes** — baseline scores and contextual
  information at session start.
* **Intra-session scales and notes** — ratings and free-text observations
  tied to each programming block as parameters change.
* **Timestamps on every entry** — each row in the output table carries date,
  time, and timezone metadata so observations, parameters, and scores can be
  aligned for analysis.
* **Analysis-ready TSV output** — tab-separated files with a documented column
  schema (:doc:`output_format`), suitable for scripts, statistical software,
  or BIDS-oriented pipelines.
* **Structured reports** — Word and PDF exports at **single-session** and
  **longitudinal** level, with tables, electrode diagrams, and session-scale
  timeline figures where applicable.

The result is a reproducible record of what was tested, when it was tested,
and how the patient responded — without replacing the implantable device's
clinical programming interface.

----

Next steps
----------

* :doc:`quickstart` — launch the application and choose a workflow
* :doc:`workflow_complete` — record a full programming session
* :doc:`longitudinal_report` — combine multiple session files into one report
