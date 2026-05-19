Quick Start
===========

This page walks you through opening the application for the first time and
choosing the right workflow for your needs.

----

Launching the Application
--------------------------

After :doc:`installation`, open **DBS Annotator** from your system's
application launcher (the installed app, not a loose ``.exe`` in a download
folder):

* **Windows** — **Start** menu entry **DBS Annotator** (from the ``.msi``
  installer or the PowerShell install script shortcut).
* **macOS** — *Applications* after installing from the ``.dmg`` or install
  script.
* **Linux** — application menu after installing the ``.deb`` or install
  script.

The main window opens on the **Home screen**.

.. image:: _static/home_screen.png
   :alt: Application home screen
   :class: screenshot-native

----

Choosing Your Workflow
-----------------------

From the home screen you can start one of three workflows:

.. list-table::
   :widths: 25 75
   :header-rows: 1

   * - Button
     - When to use it
   * - **Complete Workflow**
     - You are about to perform a DBS programming session and want to record
       stimulation parameters, clinical scales, and notes in real-time.
   * - **Annotations-only Workflow**
     - You only need timestamped text notes — no stimulation parameters or
       clinical scale values.
   * - **Create Longitudinal Report**
     - You already have multiple programming-session TSV files from the same
       subject (BIDS example:
       ``sub-XX_ses-YYYYMMDD_task-programming_run-XX_events.tsv``) from
       previous visits and want to generate a combined comparative report.

----

Interface Overview
------------------

The application window contains three persistent elements:

* **Top bar** — application title, current file name, and the Dark / Light
  theme toggle (☀ / ☾ icon).
* **Main area** — changes with each step of the workflow.
* **Bottom navigation** — *Back* and *Next* / action buttons.

Theme Toggle
^^^^^^^^^^^^

Click the **☀ / ☾** button in the top-right corner at any time to switch
between the light and dark colour scheme.  Your preference is applied
immediately and maintained between pages.

.. image:: _static/home_screen_dark.png
   :alt: Application home screen (dark theme)
   :class: screenshot-native

----

Next Steps
----------

* :doc:`workflow_complete` — **Complete Workflow**
* :doc:`workflow_annotations` — **Annotations-only Workflow**
* :doc:`longitudinal_report` — **Create Longitudinal Report**
