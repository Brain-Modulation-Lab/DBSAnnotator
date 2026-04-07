.. Clinical DBS Annotator documentation master file

Clinical DBS Annotator
======================

.. image:: _static/logo.png
   :alt: Clinical DBS Annotator
   :align: center
   :width: 180px

|

**Clinical DBS Annotator** is a desktop application for recording and analysing
Deep Brain Stimulation (DBS) clinical programming sessions.  It guides the
clinician or researcher through the full session workflow — from initial
electrode configuration and baseline scales, through real-time stimulation
adjustments, to the automatic generation of structured Word and PDF reports.

Developed at the **Brain Modulation Lab, Massachusetts General Hospital**.

.. note::
   Version **0.3 (testing)** — Windows installer available.
   Contact: lpoma@mgh.harvard.edu

----

.. toctree::
   :maxdepth: 2
   :caption: Getting Started

   installation
   quickstart

.. toctree::
   :maxdepth: 2
   :caption: User Guide

   workflow_session
   workflow_annotations
   longitudinal_report
   output_format

.. toctree::
   :maxdepth: 1
   :caption: Reference

   faq

.. toctree::
   :maxdepth: 1
   :caption: Developer Guide

   contributing

----

Quick Overview
--------------

.. list-table::
   :widths: 30 70
   :header-rows: 0

   * - **Single-session workflow**
     - Record stimulation parameters, clinical scales, and notes step-by-step.
       Export a structured report (Word / PDF) at the end.
   * - **Longitudinal report**
     - Combine multiple session files into a single comparative document with
       overview tables, electrode configuration diagrams, and timeline charts.
   * - **Free annotations**
     - Quick timestamped text notes without the full stimulation workflow.
   * - **BIDS-compliant output**
     - Data saved as ``sub-XX_ses-YYYYMMDD_task-programming_run-XX_events.tsv``.
   * - **No installation required**
     - The application ships as a single self-contained ``.exe`` (Windows).
