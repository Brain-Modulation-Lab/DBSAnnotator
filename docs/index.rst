.. DBS Annotator documentation master file

DBS Annotator
=============

.. image:: _static/logo.png
   :alt: DBS Annotator
   :align: center
   :width: 180px

|

**DBS Annotator** is a desktop application for recording and analysing
Deep Brain Stimulation (DBS) clinical programming sessions.  It guides the
clinician or researcher through the **Complete Workflow** — from initial
electrode configuration and baseline scales, through real-time stimulation
adjustments, to the automatic generation of structured Word and PDF reports.

Developed at the **Brain Modulation Lab, Massachusetts General Hospital** (Boston, USA),
the **Wyss Center for Bio and Neuroengineering** (Geneva, Switzerland), and
**Charité Universitätsmedizin Berlin** (Germany).

.. note::
   | Version |release|.
   | Copyright © Massachusetts General Hospital, Wyss Center for Bio and Neuroengineering, and Charité Universitätsmedizin Berlin.
   | Contact: lucia.poma@wysscenter.ch

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
   changelog

.. toctree::
   :maxdepth: 1
   :caption: Developer Guide

   contributing
   releasing
   api

----

Quick Overview
--------------

.. list-table::
   :widths: 30 70
   :header-rows: 0

   * - **Complete Workflow**
     - Record stimulation parameters, clinical scales, and notes step-by-step.
       Export a structured report (Word / PDF) with tables, electrode diagrams,
       and session-scale timeline charts.
   * - **Longitudinal report**
     - Combine multiple session files into a single comparative document with
       overview tables, clinical and session-scale charts, electrode diagrams,
       and programming summaries.
   * - **Annotation-only Workflow**
     - Quick timestamped text notes without the full stimulation workflow.
   * - **BIDS-compliant output**
     - Data saved as ``sub-XX_ses-YYYYMMDD_task-programming_run-XX_events.tsv``.
   * - **No installation required**
     - The application ships as a single self-contained ``.exe`` (Windows).
