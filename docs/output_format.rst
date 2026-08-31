Data format
===========

Everything the app records is written as **tab-separated text**. There is no
proprietary container, no binary blob and no export step that can silently drop
a field: what you see in the file is what was recorded.

Filenames
---------

Filenames follow the `BIDS <https://bids.neuroimaging.io/>`_ convention:

.. code-block:: text

   sub-<subject>_ses-<YYYYMMDD>_task-<task>_run-<NN>_events.tsv

with two task values:

``task-programming``
   A full session: stimulation parameters and scale ratings per configuration.

``task-notes``
   An annotations-only session: timestamped free text, nothing else.

For example:

.. code-block:: text

   sub-01_ses-20260626_task-programming_run-01_events.tsv
   sub-01_ses-20260626_task-notes_run-01_events.tsv

``run`` distinguishes several sessions on the same day and defaults to ``01``.
The subject label is sanitised to alphanumerics, so a typed ``/`` or ``..``
cannot escape into the path.

Row shape
---------

The session file is in **long form: one row per (block, scale)**.

A *block* is one stimulation configuration. If five scales are rated at a
configuration, that block contributes five rows, and each of them repeats that
block's stimulation values. This is deliberate, and it is the single most
important thing to understand about the format:

.. include:: _generated/example_rows.inc.rst

.. _why-long-not-wide:

Why long and not wide
~~~~~~~~~~~~~~~~~~~~~

One row per block with a column per scale looks tidier and is worse. The column
set would become indication-specific — an OCD session and a Parkinson's session
would have different columns — so pooling them would need an outer join on
mismatched headers, and adding a scale mid-study would change the header of
every file written afterwards.

In long form, a site using different scales simply writes different *rows*, and
everything pools with a concatenation. It is also the shape that pivots without
reshaping:

.. code-block:: python

   import pandas as pd

   df = pd.read_csv(path, sep="\t")
   wide = df.pivot_table(
       index=["session_ID", "block_ID"],
       columns="scale_name",
       values="scale_value",
   )

Which rows are which
~~~~~~~~~~~~~~~~~~~~

``is_initial`` separates the two kinds of entry:

``is_initial = 1``
   The **baseline** block: the clinical assessment and the settings the patient
   arrived on, recorded before any configuration is tried. Excluded from
   "configurations tested" and from the tested-parameter ranges in reports.

``is_initial = 0``
   A **recording** block: one configuration that was tried and rated.

.. warning::

   Read ``is_initial`` numerically, not as a truthy string. Some files write
   ``0.0``/``1.0``, and ``df.is_initial.astype(bool)`` is ``True`` for the
   *string* ``"0.0"`` — which silently moves the baseline into the tested set.
   Use ``df.is_initial.astype(float).eq(1)``.

Omitted ratings
~~~~~~~~~~~~~~~

A scale that was not assessed at a block is written as ``NaN`` in
``scale_value``. Read it with:

.. code-block:: python

   df = pd.read_csv(path, sep="\t", na_values=["NaN"])

Timestamps
----------

Every row carries ``date`` (``YYYY-MM-DD``), ``time`` (``HH:MM:SS``) and
``timezone``. Combine the first two:

.. code-block:: python

   df["when"] = pd.to_datetime(df.date + " " + df.time)

``timezone`` holds a platform-supplied name followed by a UTC offset, for
example ``W. Europe Daylight Time +0200``. Only the offset half is portable —
``pd.to_datetime`` cannot parse the display name — so extract it if you need a
timezone-aware index:

.. code-block:: python

   offset = df.timezone.str.extract(r"([+-]\d{4})")[0]

Amplitudes and current steering
-------------------------------

``left_amplitude`` and ``right_amplitude`` hold either a single value
(``4.5``) or, when current is shared across several cathodes, the per-contact
values joined by an underscore in cathode order:

.. code-block:: text

   left_cathode     E2b_E2c
   left_amplitude   3.3_2.2      -> 5.5 mA total, 60 % / 40 %

The split is part of the configuration, not a detail: ``3.3_2.2`` and
``2.2_3.3`` across the same two contacts stimulate different tissue. To recover
the delivered dose:

.. code-block:: python

   total = df.left_amplitude.astype(str).str.split("_").apply(
       lambda parts: sum(float(p) for p in parts if p)
   )

Contacts are written in the app's token grammar: ``case`` for the can, ``E2``
for a ring contact, ``E2b`` for one segment of a segmented level, and ``_`` to
join several. ``E2b_E2c`` therefore means two segments of level 2 are active.

Session columns
---------------

.. include:: _generated/session_columns.inc.rst

Annotations columns
-------------------

.. include:: _generated/annotation_columns.inc.rst

Worked example
--------------

The file used throughout this documentation, and in the app's own test suite, is
a real 7-configuration session with five session scales:

:download:`sub-01_ses-20260626_task-programming_run-01_events.tsv
<_generated/sub-01_ses-20260626_task-programming_run-01_events.tsv>`
