Frequently Asked Questions
==========================

General
-------

**Does the application require an internet connection?**

No.  The application is fully offline.  It only reads and writes local files.

**Is my patient data sent anywhere?**

No.  All data stays on your local machine.  No telemetry, no cloud sync.

**Which DBS systems are supported?**

The application is system-agnostic for data recording.  Electrode visualisation
supports leads from Medtronic (including Percept PC / RC), Abbott (Infinity),
Boston Scientific (Vercise) and PINS families.
If your lead is not listed, use the closest equivalent or contact the
development team to request it be added.

**Can I use the application on a shared clinical workstation?**

Yes.  The application is easily installable and does not require installation or registry entries.

----

Files & Data
------------

**Where are my data files saved?**

In the folder you selected in Step 0 of the session workflow.  The application
never writes files outside that folder.

**Can I open the TSV files in Excel?**

Yes.  In Excel: *File → Open*, select the ``.tsv`` file, and in the Text Import
Wizard choose **Tab** as the delimiter.

Alternatively, double-click the file — Windows may open it in Excel
automatically if Excel is installed.

**Can I edit the TSV file manually?**

You can, but be careful:

* Do not change column headers.
* Do not delete or reorder rows.
* Do not change the ``is_initial`` values.
* Save as Tab-delimited TSV, not as ``.xlsx``.

**What happens if the application crashes mid-session?**

All entries are written to disk immediately as they are recorded in the TSV file.  You will not
lose any data that was successfully recorded before the crash.  Reopen the
application, start a new session pointing to the same folder, and the existing
file will be detected.

**Can I merge two TSV files from the same session?**

Manually: open both files in a text editor and copy the rows from the second
file (excluding the header row) to the end of the first.  Make sure block IDs
are unique after merging.

----

Reports
-------

**The report generation dialog asks about scale optimisation.  What is that?**

The application highlights the "best" stimulation configuration in green in the
Session Data table.  The scale optimisation dialog lets you define what "best"
means for each scale:

* **Min** — the entry with the lowest value is best (e.g. UPDRS — lower motor
  score = better).
* **Max** — the entry with the highest value is best (e.g. Mood VAS — higher
  mood = better).
* **Custom** — the entry closest to a target value you specify.

Uncheck a scale to exclude it from the calculation.

**The report sections dialog appeared but I only want a summary table.
Which sections should I check?**

Check only **Sessions Overview** (for a quick one-table overview) or
**Programming Summary** (for parameter ranges).  Uncheck the others.

**Word export works but PDF export fails.**

PDF conversion requires Microsoft Word to be installed on the machine, or
LibreOffice in headless mode.  If neither is available:

1. Export as Word (``.docx``) instead.
2. Open the ``.docx`` in Word and print to PDF manually (*File → Export →
   Create PDF/XPS*).

**The electrode diagrams are missing from the report.**

This happens when the electrode model field is empty in the TSV.  Ensure that
you selected an electrode model in Step 1 before recording entries.

----

Troubleshooting
---------------

**The application does not start / shows a black window.**

Try running it as administrator (right-click → *Run as administrator*).  This
is sometimes needed on machines with strict execution policies.

**The application is very slow on first launch.**

Windows Defender or other antivirus software may be scanning the executable.
Add the application folder to your antivirus exclusion list.

**I see "No session data found" when trying to export a longitudinal report.**

Check that:

* At least one ``.tsv`` file is loaded.
* The loaded files contain rows with ``is_initial = 0`` (session entries, not
  just baseline).
* The files are not empty or corrupted.

**The scale optimisation dialog shows no scales.**

The longitudinal report requires at least one session file with recorded scale
values (``scale_name`` and ``scale_value`` columns populated) in
``is_initial = 0`` rows.  If your files only contain initial entries, the
dialog cannot compute best-entry highlighting — proceed by clicking OK without
making any selection.

----

Contact & Support
-----------------

For bug reports, feature requests, or questions:

| **Lucia Poma** — lucia.poma@wysscenter.ch
