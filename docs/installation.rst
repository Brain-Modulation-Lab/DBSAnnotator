Installation
============

DBS Annotator is a **self-contained desktop application** — no Python or
extra libraries are required to run the packaged build.  Session data are
plain ``.tsv`` files in a folder you choose when you start a session.

----

For end users
-------------

You can find installation files for **Windows** (``.msi``), **macOS**
(``.dmg``), and **Linux** (``.deb``) on
`GitHub Releases <https://github.com/Brain-Modulation-Lab/DBSAnnotator/releases>`_.

However, the files are **unsigned**, so a warning may appear during
installation or on first launch.  You must accept the risk and continue.
On Windows, see :ref:`windows-smartscreen` if SmartScreen blocks the app.

In some cases — for example when your organization has strict settings — a
direct download may not be possible.  Use the **install commands below** for
your operating system.

----

.. _windows-smartscreen:

Windows — SmartScreen warnings
------------------------------

Release builds are not code-signed.  **Windows Defender SmartScreen** may
block the installer (``.msi``) or the application on first launch.

If you see **"Windows protected your PC"** or **"Microsoft Defender SmartScreen
prevented an unrecognized app from starting"**:

1. Click **More info** (or **Show more** on newer Windows builds).
2. Click **Run anyway** (installer) or **Run** (application).

If your organization blocks unsigned software entirely, use the PowerShell
install command below (portable build under your user profile), or ask IT for
an exception.

----

Windows — install via PowerShell
--------------------------------

In an **open PowerShell** window:

.. code-block:: powershell

   irm https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.ps1 | iex

From **cmd.exe** (or if execution policy blocks scripts):

.. code-block:: bat

   powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.ps1 | iex"

The script fetches the latest Windows portable ``.zip`` from GitHub Releases,
unpacks under ``%LOCALAPPDATA%\\WyssGeneva\\DBSAnnotator\\app``, and creates a
Start Menu shortcut.

----

macOS / Linux — shell install
-----------------------------

**macOS** and **Linux** use the same install script.  It needs **Python 3**
and ``curl`` or ``wget``.  On macOS it prefers the release **raw** ``.tar.gz``,
otherwise the ``.dmg``.  On Linux (x86_64) it prefers the raw ``.tar.gz``,
otherwise the published ``.deb``.

.. code-block:: sh

   curl -LsSf https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.sh | sh

.. code-block:: sh

   wget -qO- https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.sh | sh

On **macOS**, if you install from the ``.dmg`` manually instead: open the disk
image from GitHub Releases and drag **DBSAnnotator** to *Applications*.  On
first launch, right-click → **Open** → **Open** again (required once when the
app is not notarized).

On **Linux** non-x86_64 systems, install the ``.deb`` from Releases manually or
build from source (see :doc:`contributing`).

----

Updating
--------

Updating the application does **not** change your session ``*_events.tsv``
files — they stay in the folders you chose in the app.

Re-run the same install command
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Use the **same one-liner** as for a fresh install to pull the latest release:

**Windows:**

.. code-block:: powershell

   irm https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.ps1 | iex

**macOS / Linux:**

.. code-block:: sh

   curl -LsSf https://raw.githubusercontent.com/Brain-Modulation-Lab/DBSAnnotator/main/scripts/install.sh | sh

Automatic update notification
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

When enabled, the app checks GitHub Releases (about once per day) and notifies
you if a newer version is available.  No patient or session data are sent.
Toggle checks from **Help**, or opt out on the update dialog.  See :doc:`faq`
(*How does the automatic update checker work?*).

Installer from GitHub Releases
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can also download a newer ``.msi``, ``.dmg``, or ``.deb`` from
`GitHub Releases <https://github.com/Brain-Modulation-Lab/DBSAnnotator/releases>`_
and run it over the previous install.

----

Data storage
------------

The application does not use a database or registry entries for clinical
data.  All recordings are tab-separated ``.tsv`` files in the output folder
you select at session start.  Column schema: :doc:`output_format`.
