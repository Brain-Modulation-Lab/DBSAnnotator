import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/bids_sidecar.dart';
import '../core/safe_file.dart';
import '../core/timestamps.dart';
import '../core/session/tsv_kind.dart';
import '../report/annotations_report.dart';
import '../report/session_docx.dart' show DocxPageSize;
import 'bids_export.dart';
import 'save_target.dart';
import 'share_util.dart';
import 'theme.dart';

/// Annotations workflow, structured like the Complete-Workflow wizard but
/// shorter: a common **File** step (patient / run, New or Open a BIDS
/// `task-notes` TSV) followed by a **Notes** step (timestamped notes appended
/// to an in-memory list, autosaved to the chosen file and exported via the OS
/// share sheet). Fully offline; the TSV is drop-in for the desktop app.
class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({super.key});

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  // Serialised, atomic autosave to the user's file. See [SafeFileWriter].
  final _writer = SafeFileWriter();

  final _subjectCtrl = TextEditingController();
  final _runCtrl = TextEditingController(text: '01');
  final _noteCtrl = TextEditingController();
  final _entries = <Annotation>[];

  int _currentStep = 0;
  // Chosen save path (from New/Open); when set, notes autosave to it.
  String? _savePath;

  /// Anchors the iPadOS share popover to the export button. See
  /// [shareOriginFrom].
  final _exportKey = GlobalKey();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _runCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// The BIDS entities for everything this screen writes — the notes TSV, its
  /// sidecar, and the report derivative — so all three carry the same ones.
  ///
  /// [subject] and [run] are free text that ends up in a path, so they go
  /// through the sanitisers; run is an *index* in BIDS, hence `index` rather
  /// than `label`.
  BidsName _bidsName({String? subject, String? run}) {
    final s = BidsName.label(subject ?? _subjectCtrl.text.trim());
    return BidsName(
      subject: s.isEmpty ? 'unknown' : s,
      session: BidsName.sessionStamp(DateTime.now()),
      task: 'notes',
      run: BidsName.index(run ?? _runCtrl.text.trim()),
    );
  }

  /// Write the `_beh.json` sidecar beside [tsvPath]; see the session screen's
  /// copy for why this is best-effort and silent.
  Future<void> _writeSidecar(String tsvPath) async {
    try {
      final json = tsvPath.replaceFirst(RegExp(r'\.tsv$'), '.json');
      if (json == tsvPath || File(json).existsSync()) return;
      final contract = await loadTsvContract();
      await File(
        json,
      ).writeAsString(annotationSidecarJson(contract, appVersion: appVersion));
    } catch (_) {
      // No sidecar is a documentation loss, not a data loss.
    }
  }

  // ---- Step 0: File (shared shape with the Complete-Workflow wizard) ----

  Future<void> _newSession() async {
    final subject = _subjectCtrl.text.trim().isEmpty
        ? '01'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = _bidsName(subject: subject, run: run).filename;
    final NewTsvTarget? target;
    try {
      target = await createNewTsv(
        dialogTitle: 'Create new notes TSV',
        fileName: name,
        header: writeAnnotations(const []), // header only
      );
    } catch (e) {
      if (mounted) _snack('Could not create $name: $e');
      return;
    }
    if (target == null) return; // dialog shown but cancelled
    if (target.fellBack && mounted) {
      _snack('No file dialog available; saved to ${target.location}');
    }
    final p = target.path;
    if (p != null) await _writeSidecar(p);
    if (!mounted) return;
    setState(() {
      _entries.clear();
      _savePath = p;
      _subjectCtrl.text = subject;
      _runCtrl.text = run;
      _currentStep = 1;
    });
    _snack('New notes file: ${target.location}');
  }

  Future<void> _open() async {
    // `pickFile`, not `pickFiles`: file_picker 12 flipped `allowMultiple` to
    // default TRUE, so the old call would have silently started accepting a
    // multi-selection here while still compiling and passing CI.
    final PlatformFile? chosen;
    try {
      chosen = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) {
        _snack('Open dialog unavailable — on Linux install "zenity". ($e)');
      }
      return;
    }
    if (chosen == null) return;
    final picked = chosen; // non-nullable, so the setState closure can use it
    final content = await readPickedText(picked);
    if (content == null) {
      if (mounted) _snack('Could not read ${picked.name}.');
      return;
    }
    // Refuse the wrong workflow's file BEFORE anything sets `_savePath`.
    //
    // This guard is load-bearing, not defensive. `parseAnnotations` is total and
    // `sessionColumns` is a superset of `annotationColumns`, so a programming
    // TSV parses here *successfully* - one "note" per session row - and reports
    // a plausible count. `_savePath` would then point at the clinician's real
    // session file (on desktop it is the real path, not a sandbox copy), and the
    // first note autosaved `writeAnnotations`, which emits only the five
    // annotation columns. That atomically replaced every block, stimulation
    // parameter, amplitude, scale rating and program with a notes-only file, with
    // no error and no `.tmp` to recover from - SafeFileWriter faithfully
    // guaranteeing the overwrite completed.
    //
    // The three sibling readers (session_screen, single_session_report_screen,
    // longitudinal_screen) all had this check; this screen was the only one that
    // did not, and it is also the only one that writes back to the file it opened.
    final kind = sniffTsvKind(content);
    if (kind != TsvKind.notes) {
      if (mounted) _snack(tsvKindMismatch(picked.name, kind, TsvKind.notes));
      return;
    }

    final loaded = parseAnnotations(content);
    final bids = BidsName.parse(picked.name);
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        // File is oldest-first; the UI shows newest-first.
        ..addAll(loaded.reversed);
      // Autosave future notes back to the opened file (when a real path).
      _savePath = picked.path;
      if (bids != null) {
        _subjectCtrl.text = bids.subject;
        _runCtrl.text = bids.run;
      }
      _currentStep = 1;
    });
    _snack('Opened ${picked.name} (${loaded.length} notes).');
  }

  Widget _fileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient ID (sub-)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _runCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Run',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _newSession,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open existing TSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _entries.isEmpty
              ? 'Empty — add notes in the next step.'
              : '${_entries.length} notes loaded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ---- Step 1: Notes ----

  void _addNote() {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _entries.insert(0, Annotation.now(text));
      _noteCtrl.clear();
    });
    _autosave();
  }

  /// Rewrite the TSV after each insert when a save path was chosen (desktop
  /// autosaves every entry). No-op when there is no path.
  ///
  /// Goes through [SafeFileWriter] so overlapping inserts cannot interleave and
  /// a crash mid-write cannot truncate the user's notes file.
  Future<void> _autosave() async {
    final path = _savePath;
    if (path == null) return;
    try {
      // File is oldest-first; the UI list is newest-first.
      await _writer.write(path, writeAnnotations(_entries.reversed.toList()));
    } catch (e) {
      if (mounted) _snack('Autosave failed: $e');
    }
  }

  Future<void> _export() async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting.');
      return;
    }
    await exportFile(
      context,
      filename: _bidsName().filename,
      anchor: _exportKey,
      // Oldest-first in the file (the UI shows newest-first).
      build: () async => (
        bytes: utf8.encode(writeAnnotations(_entries.reversed.toList())),
        warning: null,
      ),
    );
  }

  /// Export these notes as a one-subject BIDS dataset (zipped); see the session
  /// screen's copy for what the tree contains and why it exists.
  Future<void> _exportBids() async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting.');
      return;
    }
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    if (!mounted) return;
    final oldestFirst = _entries.reversed.toList();
    await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: [
        datasetEntry(
          name: _bidsName(),
          tsv: writeAnnotations(oldestFirst),
          contract: contract,
          kind: 'annotation_tsv',
          acqTime: oldestFirst.first.acqTime,
        ),
      ],
    );
  }

  /// Export the notes as a report. Until now this screen could only write a
  /// TSV, while the home card promised "Notes -> report".
  Future<void> _exportReport({required bool docx}) async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting a report.');
      return;
    }
    final name = _bidsName();
    final subject = name.subject;
    // A report is a derivative, not raw data — `_report` is not a BIDS suffix.
    // Same entities as the TSV so the two files sort together.
    final filename = name
        .withSuffix('report', extension: docx ? 'docx' : 'pdf')
        .filename;

    await exportFile(
      context,
      filename: filename,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        // Oldest first is the builder's job; it sorts what it is given.
        final data = buildAnnotationsReportData(
          entries: _entries,
          subjectId: subject,
          sourceFile: _savePath == null ? '' : pickedBasename(_savePath!),
        );
        if (docx) {
          return (
            bytes: buildAnnotationsDocx(data, pageSize: DocxPageSize.a4),
            warning: null,
          );
        }
        final report = await buildAnnotationsPdf(data);
        return (
          bytes: report.bytes,
          warning: report.lostCharacters
              ? 'Some characters could not be rendered in the PDF and were '
                    'replaced with "?". Add the IBM Plex fonts to assets/fonts/ '
                    'for full Unicode, or export to Word instead.'
              : null,
        );
      },
    );
  }

  Widget _notesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _noteCtrl,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addNote,
          icon: const Icon(Icons.add),
          label: const Text('Insert timestamped note'),
        ),
        const SizedBox(height: 8),
        MenuAnchor(
          builder: (context, controller, child) => OutlinedButton.icon(
            key: _exportKey,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.ios_share),
            label: const Text('Export'),
          ),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _exportReport(docx: false),
              child: const Text('Report (PDF)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.description_outlined),
              onPressed: () => _exportReport(docx: true),
              child: const Text('Report (Word)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.table_chart_outlined),
              onPressed: _export,
              child: const Text('Data (TSV)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.folder_zip_outlined),
              onPressed: _exportBids,
              child: const Text('BIDS dataset (zip)'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text(
          'Inserted notes (${_entries.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          const Center(child: Text('No notes yet.'))
        else
          // Review table of the timestamped notes (newest first), so entries
          // can be checked instead of relying on the insert snackbar.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 96,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Note')),
              ],
              rows: [
                for (final e in _entries)
                  DataRow(
                    cells: [
                      DataCell(Text(_noteDate(e))),
                      DataCell(Text(_noteTime(e))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            e.notes,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- Wizard scaffold (mirrors session_screen.dart) ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotations'),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepTapped: (i) => setState(() => _currentStep = i),
        onStepContinue: _currentStep < 1
            ? () => setState(() => _currentStep += 1)
            : null,
        onStepCancel: _currentStep > 0
            ? () => setState(() => _currentStep -= 1)
            : null,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (details.onStepContinue != null)
                  FilledButton.tonal(
                    onPressed: details.onStepContinue,
                    child: const Text('Next'),
                  ),
                if (details.onStepContinue != null &&
                    details.onStepCancel != null)
                  const SizedBox(width: 8),
                if (details.onStepCancel != null)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('File'),
            subtitle: const Text('Patient / run — new or open TSV'),
            isActive: _currentStep == 0,
            content: _fileStep(),
          ),
          Step(
            title: const Text('Notes'),
            subtitle: const Text('Timestamped notes → task-notes TSV'),
            isActive: _currentStep == 1,
            content: _notesStep(),
          ),
        ],
      ),
    );
  }
}

/// A note's date for the entries table, or '' when it has no usable instant.
///
/// Date and clock time are display forms of the note's single `acq_time` now,
/// not stored cells. Pre-0.5.0 notes files were the worst case: their
/// `timezone` cell held a zone NAME with no offset, so those rows could not be
/// resolved to an instant at all until `Annotation.fromMap` began backfilling
/// them from `date` + `time`.
String _noteDate(Annotation e) => recordedDate(e.acqTime);

/// A note's clock time, with the recorded UTC offset when the row carries one.
String _noteTime(Annotation e) {
  final time = recordedTime(e.acqTime);
  if (time.isEmpty) return '';
  final offset = offsetFromTimezoneCell(e.acqTime);
  return offset.isEmpty ? time : '$time (UTC$offset)';
}
