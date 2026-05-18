Session Workflow
================

The session workflow guides you through a complete DBS programming session in
**four steps**.  Data is saved automatically after each entry; you never need to
press a manual "Save" button.

.. raw:: html

   <p><em>▶ <a href="_static/videos/session_overview.mp4">Watch: Full session workflow overview (video)</a></em></p>

----

Step 0 — File & Patient Setup
------------------------------

.. image:: _static/step0.png
   :alt: Step 0 – File setup screen
   :width: 680px

On this screen you configure where data will be saved and identify the patient.

Fields
^^^^^^

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Field
     - Description
   * - **Output folder**
     - Browse to the directory where the ``.tsv`` file will be written.
       Tip: use a BIDS-structured folder, e.g.
       ``sub-01/ses-20250101/``.
   * - **Patient ID**
     - Free-text identifier (e.g. ``sub-01``).  Used in the BIDS filename.
   * - **Session label**
     - Optional label appended to the filename (e.g. ``run-01``).
   * - **Run number**
     - Auto-incremented integer used in the BIDS filename.

Output filename
^^^^^^^^^^^^^^^

The application generates a BIDS-compliant filename automatically::

   sub-<ID>_ses-<YYYYMMDD>_task-programming_run-<NN>_events.tsv

If a file with that name already exists, you are asked whether to append to
it or create a new run.

.. note::
   Click **Next** once all fields are filled in.  The file is created on disk
   at this point.

----

Step 1 — Initial Configuration
-------------------------------

.. image:: _static/step1.png
   :alt: Step 1 – Initial configuration screen
   :width: 680px

.. raw:: html

   <p><em>▶ <a href="_static/videos/step1_electrode.mp4">Watch: Electrode selection and initial parameters (video)</a></em></p>

This step records the **baseline** state at the beginning of the session
(``is_initial = 1`` rows in the TSV).

Electrode Model
^^^^^^^^^^^^^^^

Select the implanted electrode model from the dropdown.  The application
supports all common Medtronic Percept, Abbott, and Boston Scientific leads.
An interactive diagram of the selected electrode is displayed immediately.

.. image:: _static/electrode_diagram.png
   :alt: Interactive electrode contact diagram
   :width: 340px

Contact Selection
^^^^^^^^^^^^^^^^^

Click directly on the electrode diagram to select contacts:

* **Cathode (−)** — primary stimulating contact(s); highlighted in blue.
* **Anode (+)** — return contact; highlighted in red.

For **directional leads** (e.g. Medtronic SenSight), you can select
individual directional segments (A, B, C) independently for each level.

.. tip::
   You can select multiple cathodes.  The amplitude split widget below the
   diagram lets you distribute the total current across selected contacts
   by percentage.

Stimulation Parameters
^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Parameter
     - Notes
   * - **Amplitude (mA)**
     - Enter total amplitude.  If multiple cathodes are selected, use the
       split widget to assign percentages.
   * - **Frequency (Hz)**
     - Stimulation frequency.
   * - **Pulse width (µs)**
     - Pulse width.
   * - **Group**
     - Stimulation group label (e.g. A, B, C, D).

Both the **Left** and **Right** hemispheres have independent parameter panels.

Baseline Clinical Scales
^^^^^^^^^^^^^^^^^^^^^^^^^

Below the stimulation parameters you will find a panel for **baseline clinical
scales** (validated rating instruments recorded once at the start of the
session).  Click a **preset button** (OCD, MDD, PD, ET, Dystonia, TS) to load
the standard scale set for that indication, or use the settings control to
customise presets.

Built-in clinical presets (Step 1):

* **OCD** — Y-BOCS, Y-BOCS-o, Y-BOCS-c, MADRS, OCI-R
* **MDD** — MADRS, HAM-D, BDI-II
* **PD** — MDS-UPDRS, UPDRS-III, PDQ-39, UDysRS
* **ET** — FTM-TRS, TETRAS
* **Dystonia** — BFMDRS, TWSTRS
* **TS** — YGTSS, PUTS, TS-CGI, Y-BOCS

Each scale has a **slider** with arrow buttons and a numeric display.  Press
the **✕** button on a slider to mark that scale as "not assessed" (stored as
``NaN`` and excluded from reports).

.. raw:: html

   <p><em>▶ <a href="_static/videos/step1_scales.mp4">Watch: Recording baseline clinical scales (video)</a></em></p>

----

Step 2 — Scale Selection
-------------------------

.. image:: _static/step2.png
   :alt: Step 2 – Scale selection screen
   :width: 680px

Choose which clinical scales to track **during the session** (i.e. at each
stimulation configuration tested).

Built-in presets
^^^^^^^^^^^^^^^^

Use the preset buttons to load a standard **session scale** set (rated at each
stimulation configuration during programming).  All built-in session scales use
a **0–10** numeric range with slider controls.

* **OCD** — Obsessions, Compulsions, Anxiety, Mood, Energy
* **MDD** — Rumination, Anxiety, Mood, Energy
* **PD** — Tremor, Rigidity, Bradykinesia, Dyskinesia, Gait / balance,
  Paresthesia, Speech difficulty
* **ET** — Action tremor, Resting tremor, Paresthesia, Speech difficulty
* **Dystonia** — Muscle contractions, Abnormal posture, Pain
* **TS** — Tic severity, Premonitory urge, Control over tics, Anxiety,
  Impulsivity

Custom scales
^^^^^^^^^^^^^

Click **+ Add scale** to define a custom scale with a name and a numeric
range (min / max).  Custom scales are saved for the current session via the
session-scales settings dialog.

----

Step 3 — Active Recording
--------------------------

.. image:: _static/step3.png
   :alt: Step 3 – Active recording screen
   :width: 680px

.. raw:: html

   <p><em>▶ <a href="_static/videos/step3_recording.mp4">Watch: Real-time recording in Step 3 (video)</a></em></p>

This is the main working screen during the programming session.

Adjusting Stimulation Parameters
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Modify stimulation parameters the same way as in Step 1.  The electrode
diagram and parameter fields are fully editable.

Recording an Entry
^^^^^^^^^^^^^^^^^^^

1. Adjust the stimulation parameters to the new configuration.
2. Fill in the clinical scale sliders.
3. Optionally add a free-text **note** in the Notes field.
4. Click **Record entry** (or press ``Enter``).

Each recorded entry is appended as a new row in the TSV file with the current
timestamp.

.. image:: _static/step3_entry_recorded.png
   :alt: Entry recorded confirmation
   :width: 400px

Session Table
^^^^^^^^^^^^^

All recorded entries are displayed in a live table at the bottom of the
screen.  The **best entry** (determined by scale optimisation) is highlighted
in green.

.. tip::
   You can record as many entries as needed within a session.  There is no
   limit on the number of configurations tested.

Exporting the Report
^^^^^^^^^^^^^^^^^^^^^

Click **Export Report** → **Word Report** or **PDF Report**.

Before the file-save dialog appears, two dialogs will be shown:

1. **Scale Optimisation** — for each clinical scale, choose whether the
   **minimum**, **maximum**, or a **custom target** value defines the "best"
   outcome.  Uncheck a scale to exclude it from the calculation.

   .. image:: _static/scale_optimization_dialog.png
      :alt: Scale optimisation dialog
      :width: 500px

2. **Report Sections** — choose which sections to include in the report.
   By default all main sections are checked.  Under **Session Data** you can
   include the timeline chart, the lateral data table, or both:

   * **Initial Clinical Notes** — baseline scores and Step 1 notes
   * **Session Data** — parent section; expand to choose:

     * **Session Data Graph** — timeline chart of session-scale values across
       recorded configurations (best entry highlighted per scale)
     * **Session Data Table** — lateral table (L/R rows) with stimulation
       parameters, scale values, and notes

   * **Electrode Configurations** — initial vs final contact diagrams
   * **Programming Summary** — session duration and parameter ranges

   .. image:: _static/report_sections_dialog.png
      :alt: Report sections dialog
      :width: 380px

3. Choose the **save location** for the report file.

Report Contents
^^^^^^^^^^^^^^^^

The generated report includes (depending on the selected sections):

* **Initial Clinical Notes** — baseline clinical scale scores and initial
  notes from Step 1.
* **Session Data** — optional **timeline chart** (one line per session scale,
  x-axis = configuration block) and/or **data table** of all recorded entries
  with stimulation parameters, scale values, and notes.  The best entry per
  scale is highlighted in green according to your optimisation choices.
* **Electrode Configurations** — visual diagrams showing the initial and
  final electrode contact selection (Left and Right hemispheres).
* **Programming Summary** — session duration, number of configurations
  tested, and parameter ranges per hemisphere.

.. raw:: html

   <p><em>▶ <a href="_static/videos/export_report.mp4">Watch: Exporting a session report (video)</a></em></p>

----

Closing the Session
-------------------

Click **Close session** when the programming session is finished.  The TSV
file is finalised and the application returns to the home screen.

.. warning::
   Do not delete or rename the ``.tsv`` file while the application is open.
   Always close the session first.
