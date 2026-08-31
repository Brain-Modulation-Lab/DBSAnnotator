Frequently asked questions
==========================

General
-------

**Does it need an internet connection?**
   No, at any point. There is no server component, no account, and no outbound
   connection. It is designed for clinical environments where network access
   cannot be assumed and patient data should not travel.

**Does it send any data anywhere?**
   No. No telemetry, no crash reporting, no analytics. Files go where you save
   them.

**Which leads are supported?**
   Medtronic (3387, 3389, 3391, SenSight B33005/B33015), Boston Scientific
   (Vercise, Vercise Directed, Cartesia HX, Cartesia X), Abbott (ActiveTip,
   Infinity), PINS Medical (L301–L303) and ALEVA directSTIM — including the
   segmented models, whose levels are drawn and tapped as three separate
   segments plus a whole-level ring.

**Can I use it on a phone?**
   It will run, but the layouts are designed for a tablet. On a narrow screen the
   two-column steps stack into one, which works but involves more scrolling than
   is comfortable during a live session.

Files and data
--------------

**Where are the files saved?**
   Wherever you choose in the platform's file picker or share sheet. The app does
   not keep a hidden copy.

**Can I open the TSV in Excel?**
   Yes. It is tab-separated text. Be aware that Excel will try to reinterpret
   some values — a scale name that looks like a date, for instance — so for
   analysis prefer pandas or R, and see :doc:`output_format`.

**Are files written by different versions compatible?**
   Yes. The format is defined by a committed contract, and readers tolerate
   missing columns, so an older file opens in a newer app.

**What happens if the app crashes mid-session?**
   Every insert is written to the file as it happens, and writes are atomic — the
   new content is written alongside and then swapped in, so an interrupted write
   leaves the previous file intact rather than a truncated one. You lose at most
   the entry you were typing.

**Why is there a row per scale instead of a row per configuration?**
   So that data pools across sites that rate different scales. See
   :ref:`why-long-not-wide`.

Reports
-------

**Why is nothing highlighted green in my report?**
   Because no scale targets have been set, so nothing has been ranked. Set them
   at export, or from the Recording step. See :ref:`scale-targets`.

**Why does the report say "last recorded configuration" rather than "final"?**
   Because the data does not record that a clinician confirmed a choice — only
   which block came last. See :ref:`what-the-reports-do-not-say`.

**A character in my note came out as a question mark.**
   The PDF exporter's built-in font covers Latin-1 only. Adding the two IBM Plex
   Sans files described in :doc:`installation` gives full Unicode coverage; Word
   export is unaffected either way. The app warns whenever a character was
   replaced, so this never happens silently.

**Can I get the report as a Word file I can edit?**
   Yes — both formats come from the same numbers, so the ``.docx`` says exactly
   what the PDF does.

Troubleshooting
---------------

**The file picker does not open on Linux.**
   Desktop Linux needs ``zenity`` or ``kdialog`` for native dialogs. Without
   one, exports fall back to saving in a well-known directory and the
   confirmation message names the exact path used.

**Opening a file says it is the wrong kind.**
   The app checks a file's columns before loading it, so an annotations file
   cannot be opened as a session. Use the workflow that matches the file, or
   *Single session report*, which detects the kind and reports accordingly.

**The lead diagram does not match the patient's implant.**
   Check the electrode model. When a file is opened, the app adopts the model
   named inside it and tells you if that name is not in the catalogue.
