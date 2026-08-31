import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/safe_file.dart';
import '../report/annotations_report.dart';
import '../report/session_docx.dart' show DocxPageSize;
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

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ---- Step 0: File (shared shape with the Complete-Workflow wizard) ----

  Future<void> _newSession() async {
    final subject =
        _subjectCtrl.text.trim().isEmpty ? '01' : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = BidsName(
      subject: subject,
      session: BidsName.sessionStamp(DateTime.now()),
      task: 'notes',
      run: run,
    ).filename;
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Create new notes TSV',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['tsv'],
      );
    } catch (_) {
      // Linux desktop opens dialogs via zenity/kdialog; fall back to the app
      // documents dir when it's absent (a real dialog appears on a tablet).
      final dir = await getApplicationDocumentsDirectory();
      await Directory(dir.path).create(recursive: true);
      path = '${dir.path}/$name';
      if (mounted) _snack('No file dialog available; saving to $path');
    }
    if (path == null) return; // dialog shown but cancelled
    final p = path.endsWith('.tsv') ? path : '$path.tsv';
    try {
      await File(p).writeAsString(writeAnnotations(const [])); // header only
    } catch (e) {
      if (mounted) _snack('Could not create $p: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.clear();
      _savePath = p;
      _subjectCtrl.text = subject;
      _runCtrl.text = run;
      _currentStep = 1;
    });
    _snack('New notes file: $p');
  }

  Future<void> _open() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        _snack('Open dialog unavailable — on Linux install "zenity". ($e)');
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    String content;
    try {
      content = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
    } catch (_) {
      if (mounted) _snack('Could not read ${picked.name}.');
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
    final subject = _subjectCtrl.text.trim().isEmpty
        ? 'unknown'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = BidsName(
      subject: subject,
      session: BidsName.sessionStamp(DateTime.now()),
      task: 'notes',
      run: run,
    );

    await exportFile(
      context,
      filename: name.filename,
      anchor: _exportKey,
      // Oldest-first in the file (the UI shows newest-first).
      build: () async => (
        bytes: utf8.encode(writeAnnotations(_entries.reversed.toList())),
        warning: null,
      ),
    );
  }

  /// Export the notes as a report. Until now this screen could only write a
  /// TSV, while the home card promised "Notes -> report".
  Future<void> _exportReport({required bool docx}) async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting a report.');
      return;
    }
    final subject = BidsName.label(_subjectCtrl.text.trim()).isEmpty
        ? 'unknown'
        : BidsName.label(_subjectCtrl.text.trim());
    final run = BidsName.label(_runCtrl.text.trim()).isEmpty
        ? '01'
        : BidsName.label(_runCtrl.text.trim());
    final stamp = BidsName.sessionStamp(DateTime.now());
    final filename = 'sub-${subject}_ses-${stamp}_task-notes_run-${run}_report'
        '.${docx ? 'docx' : 'pdf'}';

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
          sourceFile: _savePath == null
              ? ''
              : _savePath!.replaceAll(r'', '/').split('/').last,
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
          ],
        ),
        const Divider(height: 32),
        Text('Inserted notes (${_entries.length})',
            style: Theme.of(context).textTheme.titleMedium),
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
                  DataRow(cells: [
                    DataCell(Text(e.date)),
                    DataCell(Text('${e.time} (${e.timezone})')),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(e.notes,
                          maxLines: 4, overflow: TextOverflow.ellipsis),
                    )),
                  ]),
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
        actions: const [
          TextSizeButtons(),
          HelpButton(),
          ThemeToggleButton()
        ],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepTapped: (i) => setState(() => _currentStep = i),
        onStepContinue: _currentStep < 1
            ? () => setState(() => _currentStep += 1)
            : null,
        onStepCancel:
            _currentStep > 0 ? () => setState(() => _currentStep -= 1) : null,
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
