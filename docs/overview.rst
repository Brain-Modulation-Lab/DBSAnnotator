Overview
========

DBS Annotator was developed to improve how deep brain stimulation (DBS)
programming sessions are documented, reviewed, and analysed over time. During a
visit, clinicians and researchers collect observations, adjust stimulation
parameters, and record scale ratings. The application keeps these elements
together in a structured, timestamped record that remains practical to use at
the bedside or in the clinic.

----

Clinical and technical context
------------------------------

Some main limitations come up often in routine practice.

**Untimestamped observations.**
Clinicians and researchers make observations during programming that inform
contact selection, titration, and follow-up. Comments on side effects,
subjective improvement, or electrode position are clinically useful, but they
are hard to use in analysis when they cannot be aligned with the stimulation
configuration and scale ratings from the same moment.

**Incomplete parameter logs from device software.**
Currently, sensing-enabled DBS systems store stimulation parameters reliably when
stimulation uses the central contacts employed for impedance sensing.
Configurations on the most dorsal or ventral contact, or on a ring electrode,
are frequently tested during programming but do not appear in the device log.
Reconstructing the full set of tested settings then falls to manual notes.

**Difficulty aggregating longitudinal data.**
Tracking clinical scores or in-session evaluations across visits often means
collating notes, screenshots, and spreadsheets. Without a common format and
timestamps, comparative review and research analysis are slow and error-prone.

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
  timeline figures where applicable (:doc:`output_format`).

The application does not replace the implantable device's clinical programming
interface. It provides a reproducible record of what was tested, when, and how
the patient responded.

----

Next steps
----------

* :doc:`quickstart` — launch the application and choose a workflow
* :doc:`workflow_complete` — record a full programming session
* :doc:`longitudinal_report` — combine multiple session files into one report
* :doc:`output_format` — data file structure and export formats
