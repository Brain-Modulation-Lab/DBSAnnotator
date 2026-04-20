Installation
============

DBS Annotator ships as a **single self-contained executable** — no
Python, no libraries, no system configuration required.

----

Windows
-------

Requirements
^^^^^^^^^^^^

* Windows 10 or Windows 11 (64-bit)
* ~150 MB of free disk space
* No administrator rights needed to *run* the application

Steps
^^^^^

1. Download the installer or the standalone ``.exe`` file provided by your lab.
2. **If you received an installer (``.msi`` or ``setup.exe``):**

   a. Double-click the installer.
   b. Follow the on-screen prompts (Next → Next → Finish).
   c. A shortcut appears on your Desktop and in the Start Menu.

3. **If you received a standalone** ``DBSAnnotator.exe`` **file:**

   a. Copy the file to any folder you prefer (e.g. ``C:\Users\YourName\DBS_Tool\``).
   b. Double-click to launch — no further steps needed.

.. note::
   The first launch may take 5–10 seconds while Windows extracts bundled
   libraries.  Subsequent launches are faster.

Windows SmartScreen Warning
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Because the application is not yet signed with a commercial certificate,
Windows may display a blue *SmartScreen* warning the first time you run it.

.. image:: _static/smartscreen.png
   :alt: Windows SmartScreen dialog
   :width: 420px

To proceed:

1. Click **"More info"**.
2. Click **"Run anyway"**.

This is a one-time step per machine.

----

macOS
-----

.. note::
   A macOS build is available from the development team on request.  The steps
   below assume a ``.dmg`` disk image has been provided.

1. Open the ``.dmg`` file.
2. Drag **DBSAnnotator** to your *Applications* folder.
3. On first launch, right-click the app icon → **Open** → **Open** again in the
   dialog.  This is required once because the app is not notarised.

----

Updating
--------

To update to a newer version simply replace the old ``.exe`` / application
bundle with the new one.  Your data files (``*.tsv``) are stored separately
and are not affected.

----

Data Storage
------------

The application does **not** create a database or modify system settings.
All data is written to plain TSV files in the folder you choose at session
start.  You can back up, move, or share these files freely.
