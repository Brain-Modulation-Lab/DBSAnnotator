Overview
========

Why this exists
---------------

A DBS programming session is an experiment. The clinician moves through a series
of stimulation configurations — contacts, amplitude, pulse width, frequency — and
at each one records how the patient is doing: tremor, rigidity, mood, side
effects. The useful output is not the final setting on its own. It is the
*relationship* between what was delivered and what happened.

That relationship is the part that usually gets lost.

Vendor programming devices record what the device needs in order to stimulate.
They are not built to export research-usable data, and what they do export is
neither consistent between manufacturers nor easy to pool across patients. So
the clinical detail — the ratings, the order things were tried in, the side
effect that appeared at 4.5 mA and went away at 3.0 — ends up on paper, or in a
free-text note, or in someone's memory. None of those survive analysis.

The result is that sessions get documented twice, inconsistently, and the
scientifically interesting content is the content that gets dropped.

What it records
---------------

DBS Annotator sits alongside the programming device and records the session as
it happens:

**Stimulation, per configuration.**
   Active contacts and their polarity on each lead, amplitude (including
   current-steered splits across segmented contacts), pulse width, frequency,
   and the stimulation group. Every configuration is a numbered *block*, so the
   sequence is preserved.

**Ratings, per configuration.**
   Session scales rated at each block — the same scales throughout, so they are
   comparable — plus a baseline clinical assessment taken before stimulation
   changes begin.

**Observations.**
   Side effects and free-text notes attached to the block they were seen at, not
   to the session as a whole.

**Time.**
   Every entry is timestamped with its UTC offset. This is what makes it
   possible, afterwards, to tell a rating taken seconds after a parameter change
   from one taken after several minutes — a distinction that changes how the
   number should be read.

Design commitments
------------------

**Offline by default.** Clinical environments cannot be assumed to have network
access, and patient data should not require it. The app has no server component
and makes no outbound connections.

**One format, openly documented.** Output is tab-separated text with
:doc:`BIDS <output_format>`-style filenames. It opens in a spreadsheet, in
pandas, in R, in a text editor. There is no proprietary container and no export
step that can silently lose a field.

**Analysis-ready shape.** Data is written in long form — one row per (block,
scale) — which is the shape that pivots and groups without reshaping, and which
lets a site using a different scale set simply add rows rather than columns.

**Say only what the data supports.** Reports state "last recorded
configuration", not "final settings", because nothing in the record shows that a
clinician confirmed a choice. Where the app ranks configurations, it refuses to
do so until someone has said what "better" means for each scale. See
:ref:`what-the-reports-do-not-say`.

Who it is for
-------------

Clinicians and researchers running DBS programming sessions who want the session
documented once, in a form that is both readable in a patient record and usable
in an analysis six months later.
