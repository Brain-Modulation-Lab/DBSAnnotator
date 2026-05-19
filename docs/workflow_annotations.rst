Annotation-only Workflow
========================

The **Annotation-only Workflow** lets you record quick timestamped text notes
without going through the full stimulation workflow.  Use it for:

* In-clinic observations during a visit that does not involve parameter changes.
* Supplementary notes to attach to an existing session file.
* Any situation where you need a lightweight timestamped log.

.. raw:: html

   <p><em>▶ <a href="_static/videos/annotations_overview.mp4">Watch: Annotation-only Workflow overview (video)</a></em></p>

----

Opening the Annotation-only Workflow
------------------------------------

From the home screen click **Annotations-only Workflow**.

.. image:: _static/annotations_view.png
   :alt: Annotation-only Workflow — file setup screen
   :width: 680px

----

Recording an Annotation
------------------------

1. Type your note in the **text field** at the top of the screen.
2. Click **Add annotation** (or press ``Enter``).

The entry is immediately appended to the list below with:

* **Timestamp** — current date and time (Eastern Time, aligned with Medtronic
  Percept logs).
* **Note text** — exactly as you typed it.

.. image:: _static/annotations_list.png
   :alt: Annotation list with timestamps
   :width: 680px

Entries are saved to the TSV file in real-time; no manual save is needed.

----

Output File
-----------

Annotations are stored in the same BIDS-compliant TSV format as session data::

   sub-<ID>_ses-<YYYYMMDD>_task-annotations_run-<NN>_events.tsv

Each row contains:

.. list-table::
   :widths: 25 75
   :header-rows: 1

   * - Column
     - Content
   * - ``date``
     - Date of the annotation (``YYYY-MM-DD``)
   * - ``time``
     - Time of the annotation (``HH:MM:SS``)
   * - ``notes``
     - The annotation text

----

Exporting a Report
------------------

Click **Export Report** → **Word Report** or **PDF Report** to generate a
simple document containing the full annotation log.

The report shows:

* Patient ID and session information (from the filename).
* A table with all annotations sorted by timestamp.

----

Closing
-------

Click **Close** when finished.  The file is automatically saved and the
application returns to the home screen.
