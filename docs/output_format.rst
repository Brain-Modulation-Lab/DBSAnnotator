Data format
===========

Everything the app records is written as **tab-separated text**, with a JSON
sidecar beside it describing every column. There is no proprietary container, no
binary blob and no export step that can silently drop a field: what you see in
the file is what was recorded.

Filenames
---------

Filenames follow the `BIDS <https://bids.neuroimaging.io/>`_ entity convention:

.. code-block:: text

   sub-<subject>_ses-<YYYYMMDD>_task-<task>_run-<NN>_beh.tsv
   sub-<subject>_ses-<YYYYMMDD>_task-<task>_run-<NN>_beh.json

with two task values:

``task-programming``
   A full session: stimulation parameters and scale ratings per configuration.

``task-notes``
   An annotations-only session: timestamped free text, nothing else.

For example:

.. code-block:: text

   sub-01_ses-20260626_task-programming_run-01_beh.tsv
   sub-01_ses-20260626_task-notes_run-01_beh.tsv

``run`` distinguishes several sessions on the same day and defaults to ``01``. It
is an *index*, so it is reduced to digits and zero-padded. The subject label is
sanitised to alphanumerics, so a typed ``/`` or ``..`` cannot escape into the
path.

.. note::

   Files written before v0.5.0 end in ``_events.tsv`` and spell three columns
   ``block_ID``, ``session_ID`` and ``program_ID``. They open unchanged — the
   app detects the format from the file's columns, not from its name. See
   :ref:`bids-changes` for why the names moved.

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

   df = pd.read_csv(path, sep="\t", na_values=["n/a"])
   wide = df.pivot_table(
       index=["session_id", "block_id"],
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

A scale that was not assessed at a block is written as ``n/a``, which is what
BIDS requires for a missing or non-applicable value. Read it with:

.. code-block:: python

   df = pd.read_csv(path, sep="\t", na_values=["n/a", "NaN"])

``NaN`` is there for files written before v0.5.0, which used that spelling.

Timestamps
----------

Every row carries four time cells. Parse ``acq_time`` and ignore the rest:

.. code-block:: python

   df["when"] = pd.to_datetime(df.acq_time)   # tz-aware, ISO-8601

``acq_time`` is the whole instant with its UTC offset
(``2026-06-26T16:46:14+02:00``). ``date`` and ``time`` are the same instant split
in two, for reading in a spreadsheet, and ``timezone`` is the zone name and
offset for a human (``CEST +02:00``).

.. note::

   Files written before v0.5.0 have no ``acq_time``, and their ``timezone`` cell
   holds a platform-supplied display name — on Windows,
   ``W. Europe Daylight Time +0200``, which no date parser accepts. For those,
   combine ``date`` and ``time`` and extract the offset:

   .. code-block:: python

      when = pd.to_datetime(df.date + " " + df.time)
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

This grammar is documented in the JSON sidecar as well as here, because the
sidecar is where a downstream tool will look.

Session columns
---------------

.. include:: _generated/session_columns.inc.rst

Annotations columns
-------------------

.. include:: _generated/annotation_columns.inc.rst

The JSON sidecar
----------------

Every TSV is written with a ``_beh.json`` beside it, carrying one entry per
column with a ``LongName``, a ``Description`` and, where the column has a
physical unit, ``Units``. It is generated from the same contract as the tables
above, so the two cannot disagree.

.. include:: _generated/sidecar_example.inc.rst

The full sidecar carries one such entry per column in the tables above.

.. _bids-relationship:

Relationship to BIDS
--------------------

These files are BIDS files, not merely BIDS-*named*. That distinction is worth
spelling out, because until v0.5.0 they were the latter.

.. _bids-changes:

Why the suffix is ``_beh``
~~~~~~~~~~~~~~~~~~~~~~~~~~

``_events.tsv`` is a reserved suffix with mandatory content. The specification
requires ``onset`` as its first column and ``duration`` as its second, and states
that "each ``events.tsv`` file REQUIRES at least one corresponding data file".

A programming session has neither. There is no acquisition to measure an onset
from, and no imaging or electrophysiology recording beside it. The specification
names the correct alternative directly:

   events files that do not include the mandatory ``onset`` and ``duration``
   columns MAY be included, but MUST be labeled ``_beh.tsv`` rather than
   ``_events.tsv``.

So ``_beh.tsv``, in a ``beh/`` datatype directory, is not a compromise: it is the
suffix the specification points at for exactly this shape of file. Versions up
to 0.4.0 wrote ``_events.tsv``, which no validator would have accepted.

The same release moved ``block_ID``, ``session_ID`` and ``program_ID`` to
``block_id``, ``session_id`` and ``program_id`` (BIDS recommends snake_case
throughout), replaced ``NaN`` with ``n/a``, added ``acq_time``, and switched line
endings from CRLF to LF.

.. _bids-dataset-export:

Exporting a dataset
~~~~~~~~~~~~~~~~~~~

A single file with BIDS entities in its name is still not a BIDS *dataset*. The
specification wants a tree, and **Export → BIDS dataset** produces one as a zip,
from any of the three screens that hold session data:

.. code-block:: text

   dataset_description.json
   README
   participants.tsv
   participants.json
   sub-01/
     ses-20260626/
       sub-01_ses-20260626_scans.tsv
       beh/
         sub-01_ses-20260626_task-programming_run-01_beh.tsv
         sub-01_ses-20260626_task-programming_run-01_beh.json

The longitudinal screen is the useful place to do this: it already holds several
visits of one patient, which is exactly what the ``sub-``/``ses-`` hierarchy is
for, and a file imported as a pre-0.5.0 ``_events.tsv`` is re-emitted into the
tree as a valid ``_beh.tsv``.

Reports are derived documents, so they belong under ``derivatives/`` rather than
beside the raw data, and are written there — with their own
``dataset_description.json`` — rather than being given invented raw-data
filenames.

What is still not standard
~~~~~~~~~~~~~~~~~~~~~~~~~~

The columns themselves. Of the twenty-two in a session file, only ``notes``
resembles anything BIDS defines; ``block_id``, ``left_cathode``,
``left_amplitude`` and the rest are this application's own. That is permitted —
BIDS allows additional columns and asks that they be documented in a sidecar,
which is what the ``_beh.json`` is for — but it does mean no generic BIDS tool
will understand what a *block* is. Read this page, or the sidecar.

Worked example
--------------

The file used throughout this documentation, and in the app's own test suite, is
a real 7-configuration session with five session scales:

:download:`sub-01_ses-20260626_task-programming_run-01_beh.tsv
<_generated/sub-01_ses-20260626_task-programming_run-01_beh.tsv>`
