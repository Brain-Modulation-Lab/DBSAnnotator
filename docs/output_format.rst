Output Format
=============

This page describes the data files produced by the application and the
structure of the exported reports.

----

TSV Data File
-------------

All session data is stored as a **tab-separated values** (``.tsv``) file.
One file is created per session; rows are appended in real-time as entries
are recorded.

Filename Convention
^^^^^^^^^^^^^^^^^^^

The filename follows the `BIDS <https://bids.neuroimaging.io/>`_ specification::

   sub-<PatientID>_ses-<YYYYMMDD>_task-programming_run-<NN>_events.tsv

Examples::

   sub-01_ses-20250315_task-programming_run-01_events.tsv
   sub-01_ses-20250315_task-annotations_run-01_events.tsv

Columns
^^^^^^^

The schema tables below are generated from the code-level constants in
``dbs_annotator.config``. This keeps the docs and writer implementation in sync.

.. include:: _generated/tsv_schema.inc.rst

.. note::
   When multiple cathode contacts are active, the ``left_cathode`` /
   ``right_cathode`` field contains comma-separated contact names and the
   amplitude field stores the **total** delivered current.  The per-contact
   split (in mA) is shown in the report but not stored in a separate column.

Example rows
^^^^^^^^^^^^

.. code-block:: text

   date	time	timezone	block_id	session_ID	is_initial	scale_name	scale_value	electrode_model	program_ID	left_stim_freq	left_anode	left_cathode	left_amplitude	left_pulse_width	right_stim_freq	right_anode	right_cathode	right_amplitude	right_pulse_width	notes
   2025-03-15	10:02:31	UTC-04:00	0	0	1	MDS-UPDRS\nUPDRS-III	28\n32	SenSight B33005	A	130	Case	E1a	0.0	90	130	Case	E2	0.0	90	Baseline pre-stim
   2025-03-15	10:15:44	UTC-04:00	1	1	0	Tremor\nRigidity\nBradykinesia	6.0\n5.0\n4.0	SenSight B33005	A	130	Case	E1a,E1b	2.0	90	130	Case	E2	2.0	90	Config 1
   2025-03-15	10:28:12	UTC-04:00	2	2	0	Tremor\nRigidity\nBradykinesia	4.0\n3.0\n3.0	SenSight B33005	B	130	Case	E2A,E2B	2.5	90	130	Case	E3	2.5	90	Config 2

----

Word / PDF Reports
------------------

Reports are generated in Microsoft Word (``.docx``) format and optionally
converted to PDF.  The document structure depends on the sections selected
at export time.

Single-Session Report
^^^^^^^^^^^^^^^^^^^^^^

Sections (in order):

1. **Title** — "Clinical DBS Session Report", generated date, patient ID,
   session number.
2. **Initial Clinical Notes** *(optional)* — baseline clinical scale scores
   and any initial notes recorded in Step 1.
3. **Session Data** *(optional)* — one or both of:

   * **Session Data Graph** — matplotlib timeline chart of session-scale
     values vs configuration block (best entry per scale highlighted).
   * **Session Data Table** — lateral table (L/R rows per configuration) with
     stimulation parameters, scale values, and notes.

4. **Electrode Configurations** *(optional)* — a borderless 4-column table:

   +-------------------+-------------------+-------------------+-------------------+
   | Initial — Left    | Initial — Right   | Final — Left      | Final — Right     |
   +===================+===================+===================+===================+
   | Diagram + text    | Diagram + text    | Diagram + text    | Diagram + text    |
   +-------------------+-------------------+-------------------+-------------------+

5. **Programming Summary** *(optional)* — session duration, number of
   configurations, and amplitude / frequency / pulse-width ranges per side.

Longitudinal Report
^^^^^^^^^^^^^^^^^^^^

Sections (in order, selected at export time):

1. **Title** — "Longitudinal DBS Report", generated date, patient ID,
   list of included files.
2. **Sessions Overview** *(optional)* — clinical-scales timeline chart across
   sessions plus a one-row-per-session summary table (date, entry count,
   baseline scale names and values).
3. **Session Data** *(optional)* — session-scale timeline chart and/or
   combined table across all sessions.  The table's first column is the entry
   **date**; the best entry per session is highlighted.
4. **Electrode Configuration** *(optional)* — per-file Initial/Final diagrams
   separated by page breaks.
5. **Programming Summary** *(optional)* — per-session parameter ranges.

----

Timestamp Alignment
--------------------

All timestamps are recorded in **Eastern Time (ET)** to align with the
Medtronic Percept PC neurostimulator's internal clock.  If you are working in
a different timezone, note this when interpreting combined Percept + annotator
datasets.
