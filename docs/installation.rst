Installation
============

DBS Annotator runs on tablets and on the desktop from a single codebase. How you
install it depends on the platform, and the honest state of each is below.

.. note::

   Distribution through the per-platform app stores is planned but not yet in
   place. Until then the builds below are **research-grade**: unsigned or
   ad-hoc-signed, and installed deliberately rather than from a store listing.

Android tablet
--------------

Each tagged release attaches a signed ``.apk`` to its
`GitHub release <https://github.com/Brain-Modulation-Lab/DBSAnnotator/releases>`_.

1. On the tablet, open the release page and download ``app-release.apk``.
2. Android will ask you to allow installation from that source. This is expected
   for an app that does not come from Google Play.
3. Open the downloaded file to install.

iPadOS
------

Apple provides no sideloading path, so iPad builds are distributed through
**TestFlight**. The invitation link is published in the release notes when a
build is available.

This requires an Apple Developer account on the publishing side, which is why
iPad availability may lag behind Android.

Desktop (Linux, Windows, macOS)
-------------------------------

Desktop bundles are built for every commit and attached to the workflow run
rather than to a release, because the desktop targets exist mainly so the report
and export code is exercised on every platform. To get one, open the latest
successful run of the *App CI/CD* workflow in the
`Actions tab <https://github.com/Brain-Modulation-Lab/DBSAnnotator/actions>`_
and download ``linux-bundle`` or ``windows-bundle``.

These are unsigned, so Windows SmartScreen and macOS Gatekeeper will warn about
them.

Building from source
--------------------

The most reliable route on any platform, and the one to use if you intend to
modify anything. It needs only the
`Flutter SDK <https://docs.flutter.dev/get-started/install>`_ (Dart 3.4 or
later):

.. code-block:: bash

   git clone https://github.com/Brain-Modulation-Lab/DBSAnnotator.git
   cd DBSAnnotator
   flutter pub get
   flutter run          # on a connected tablet, emulator, or the desktop

Nothing needs generating first: the schema contract is committed, so a fresh
clone builds immediately. To confirm the checkout is sound:

.. code-block:: bash

   flutter analyze      # must report no issues
   flutter test         # runs the full suite, no device needed

On Linux the desktop build additionally needs GTK development headers:

.. code-block:: bash

   sudo apt-get install ninja-build libgtk-3-dev

Unicode in PDF reports
----------------------

The PDF exporter falls back to a built-in font that covers Latin-1 only, so a
curly quote or an accented character typed into a clinical note is replaced with
``?``. **The app tells you when this happens** — it is never silent — but to
avoid it entirely, place two font files in ``assets/fonts/``:

.. code-block:: text

   assets/fonts/IBMPlexSans-Regular.ttf
   assets/fonts/IBMPlexSans-Bold.ttf

Download the **static** TrueType builds of
`IBM Plex Sans <https://fonts.google.com/specimen/IBM+Plex+Sans>`_ (they are
OFL-licensed and redistributable). Word export is unaffected either way, since
``.docx`` uses the reader's own fonts.

Where your data goes
--------------------

Files are written where you choose to save them, via the platform's own file
picker or share sheet. The app keeps no hidden database and uploads nothing.
Application preferences — scale presets, paper size, panel order — are stored in
the OS application-support directory for the app.
