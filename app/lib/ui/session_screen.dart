import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../core/bids.dart';
import '../core/electrode/amplitude.dart';
import '../core/electrode/contact_state.dart';
import '../core/electrode/electrode_model.dart';
import '../core/electrode/stimulation_rule.dart';
import '../core/electrode/tokens.dart';
import '../core/prefs/user_prefs.dart';
import '../core/session/authoring.dart';
import '../core/session/scale_presets.dart';
import '../core/session/session_row.dart';
import '../report/report_data.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../app_info.dart';
import 'amplitude_split.dart';
import 'electrode_view.dart';
import 'list_editor_dialog.dart';
import 'report_images.dart';
import 'scales_chart_painter.dart';
import 'scale_presets_dialog.dart';
import 'save_target.dart';
import 'scale_slider.dart';
import 'share_util.dart';
import 'setting_presets_dialog.dart';
import 'stim_params_form.dart';
import 'theme.dart';

/// Complete-Workflow authoring as the desktop's 4-step wizard
/// (step0..step3_view.py), driven by a Material [Stepper]:
///
/// - Step 0 — File: patient/run, start empty or open an existing TSV.
/// - Step 1 — Initial configuration: baseline stimulation + clinical
///   scales, inserted as ONE is_initial=1 block.
/// - Step 2 — Session scales: define the (name, min, max) scale set that
///   Step 3 rates. Nothing is written to the TSV here.
/// - Step 3 — Recording: stimulation + one slider/omit row per Step-2
///   scale, inserted as is_initial=0 blocks; TSV / PDF export.
///
/// Produces the same `task-programming` TSV (via [SessionAuthoring] ->
/// buildInsertRows) that the desktop writes. Offline pattern copied from
/// annotations_screen.dart: in-memory rows, Open via file_picker, Export
/// via share_plus.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    this.catalog,
    this.limits,
    this.scalePresets,
    this.authoring,
  });

  /// Injectable for headless tests; loaded from bundled assets when null.
  final ElectrodeCatalog? catalog;
  final StimLimits? limits;
  final ScalePresets? scalePresets;

  /// Injectable for headless tests so inserted rows can be asserted without
  /// touching platform channels (export/share). A fresh one is created when
  /// null.
  final SessionAuthoring? authoring;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

/// Desktop-identical number formatting: f"{x:.2f}".rstrip("0").rstrip(".").
String _fmtValue(double v) {
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// One Step-1 clinical scale row: name + typed numeric score.
class _ClinicalScaleEdit {
  final name = TextEditingController();
  final score = TextEditingController();

  void dispose() {
    name.dispose();
    score.dispose();
  }
}

/// One session scale: defined in Step 2 (name/min/max) and rated in Step 3
/// (slider [value] + [omitted] "not assessed" toggle).
class _SessionScaleEdit {
  _SessionScaleEdit({
    required double min,
    required double max,
    String name = '',
  }) : value = min {
    this.name.text = name;
    minCtrl.text = _fmtValue(min);
    maxCtrl.text = _fmtValue(max);
  }

  final name = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  double value;
  bool omitted = false;

  double minOr(double fallback) =>
      double.tryParse(minCtrl.text.trim()) ?? fallback;
  double maxOr(double fallback) =>
      double.tryParse(maxCtrl.text.trim()) ?? fallback;

  void dispose() {
    name.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
  }
}

/// One side's stimulation inputs (form controllers + electrode contacts).
/// Shared by Step 1 and Step 3, like the desktop keeps the last-used
/// settings when moving between steps.
class _SideInputs {
  final freq = TextEditingController();
  final amp = TextEditingController();
  final pulseWidth = TextEditingController();
  Map<ContactKey, ContactState> states = {};
  ContactState caseState = ContactState.off;
  String validationError = '';

  /// Per-side enable checkbox (desktop's checkable electrode group).
  bool enabled = true;

  /// Amplitude split percentages, aligned to the active cathodes; used to
  /// serialize `left/right_amplitude` when >= 2 cathodes are active.
  List<double> ampSplit = const [];

  void dispose() {
    freq.dispose();
    amp.dispose();
    pulseWidth.dispose();
  }
}

class _SessionScreenState extends State<SessionScreen> {
  late SessionAuthoring _authoring = widget.authoring ?? SessionAuthoring();
  final _subjectCtrl = TextEditingController();
  final _runCtrl = TextEditingController(text: '01');
  // Notes are per-context: the initial-config notes persist across inserts (the
  // user keeps refining them); recording notes clear after each block.
  final _notesInitCtrl = TextEditingController();
  final _notesRecCtrl = TextEditingController();
  // Electrode/param state is INDEPENDENT per step: editing the recording config
  // must not change what the initial config shows. The recording pair is seeded
  // once from the initial pair on first entry to the Recording step.
  final _leftInit = _SideInputs();
  final _rightInit = _SideInputs();
  final _leftRec = _SideInputs();
  final _rightRec = _SideInputs();
  bool _recSeeded = false;
  final _clinicalScales = <_ClinicalScaleEdit>[];
  final _sessionScales = <_SessionScaleEdit>[];
  // Removed rows are kept here so their controllers outlive the frame in
  // which their TextField unmounts; disposed with the screen.
  final _removedClinical = <_ClinicalScaleEdit>[];
  final _removedSession = <_SessionScaleEdit>[];

  // Anchor the iPadOS share popover to whichever export button was tapped.
  // See [shareOriginFrom].
  final _exportTsvKey = GlobalKey();
  final _exportReportKey = GlobalKey();
  final _exportDocxKey = GlobalKey();

  int _currentStep = 0;
  String? _modelName;
  // Chosen save path (from New/Open); when set, inserts autosave to it.
  String? _savePath;
  // True when that path is an iOS sandbox copy rather than the user's own
  // file. See [pickedPathAutosavesToOriginal].
  bool _savePathIsSandboxCopy = false;
  // Currently-applied disease preset, for the selected pill styling.
  String? _selectedClinicalPreset;
  String? _selectedSessionPreset;
  // Selected program name (desktop program combo).
  String? _selectedProgram;
  // Per-user overrides (programs + presets), loaded async.
  UserPrefs _prefs = UserPrefs();
  late final Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts;

  @override
  void initState() {
    super.initState();
    _contracts = _loadContracts();
    loadUserPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }


  /// Report paper size from the user preference, applied to BOTH formats so the
  /// PDF and the Word document always agree.
  bool get _reportLetter =>
      (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';

  /// Effective program names (user override, else the desktop defaults).
  List<String> get _programs => _prefs.programs ?? kDefaultPrograms;

  /// Desktop default electrode (step1_view: preselect "Medtronic SenSight
  /// B33005"), so the L/R canvases render immediately instead of a placeholder.
  static const String kDefaultModel = 'Medtronic SenSight B33005';

  Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _loadContracts() async {
    final catalog = widget.catalog ?? await loadElectrodeCatalog();
    final limits = widget.limits ?? await loadStimLimits();
    final presets = widget.scalePresets ?? await loadScalePresets();
    if (_modelName == null && catalog.models.containsKey(kDefaultModel)) {
      _modelName = kDefaultModel;
    }
    return (catalog, limits, presets);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _runCtrl.dispose();
    _notesInitCtrl.dispose();
    _notesRecCtrl.dispose();
    _leftInit.dispose();
    _rightInit.dispose();
    _leftRec.dispose();
    _rightRec.dispose();
    for (final s in [..._clinicalScales, ..._removedClinical]) {
      s.dispose();
    }
    for (final s in [..._sessionScales, ..._removedSession]) {
      s.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// Amplitude cell: '' when blank, otherwise the plain total formatted via
  /// encodeAmplitude (split-across-cathodes UI is deferred; a single value
  /// is what the desktop writes when there is at most one cathode).
  static String _amplitudeCell(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final v = double.tryParse(t);
    return v == null ? t : encodeAmplitude(v, const []);
  }

  // ---- Insert (Step 1 baseline / Step 3 recording) ----

  /// True when every stim field is blank or within limits; otherwise shows
  /// the blocking snackbar (Step-1 and Step-3 inserts share this guard).
  bool _stimInRange(StimLimits limits, _SideInputs left, _SideInputs right) {
    final outOfRange = [
      rangeError(left.freq.text, limits.frequency),
      rangeError(left.amp.text, limits.amplitude),
      rangeError(left.pulseWidth.text, limits.pulseWidth),
      rangeError(right.freq.text, limits.frequency),
      rangeError(right.amp.text, limits.amplitude),
      rangeError(right.pulseWidth.text, limits.pulseWidth),
    ].whereType<String>();
    if (outOfRange.isNotEmpty) {
      _snack('Fix out-of-range stimulation values before inserting.');
      return false;
    }
    return true;
  }

  /// The 10 stimulation TSV cells from the given L/R inputs (initial or
  /// recording pair).
  Map<String, String> _stimCells(
      ElectrodeCatalog catalog, _SideInputs left, _SideInputs right) {
    final model = _modelName == null ? null : catalog.models[_modelName];
    var leftTokens = (anode: '', cathode: '');
    var rightTokens = (anode: '', cathode: '');
    if (model != null) {
      leftTokens = encodeTokens(left.states, left.caseState, model);
      rightTokens = encodeTokens(right.states, right.caseState, model);
    }
    return {
      'left_stim_freq': left.freq.text.trim(),
      'left_anode': leftTokens.anode,
      'left_cathode': leftTokens.cathode,
      'left_amplitude': _amplitudeFor(left, leftTokens),
      'left_pulse_width': left.pulseWidth.text.trim(),
      'right_stim_freq': right.freq.text.trim(),
      'right_anode': rightTokens.anode,
      'right_cathode': rightTokens.cathode,
      'right_amplitude': _amplitudeFor(right, rightTokens),
      'right_pulse_width': right.pulseWidth.text.trim(),
    };
  }

  /// Serialize a side's amplitude: an "a_b" split across cathodes when >= 2 are
  /// active (using the amplitude-split percentages), else the plain total.
  String _amplitudeFor(
      _SideInputs side, ({String anode, String cathode}) tokens) {
    final cathodes =
        tokens.cathode.split('_').where((t) => t.isNotEmpty && t != 'case').toList();
    final total = double.tryParse(side.amp.text.trim());
    if (cathodes.length >= 2 &&
        total != null &&
        side.ampSplit.length == cathodes.length) {
      return encodeAmplitude(total, side.ampSplit);
    }
    return _amplitudeCell(side.amp.text);
  }

  /// Navigate to [step], seeding the recording config from the initial config
  /// the first time the Recording step (3) is opened — so recording STARTS from
  /// the initial config but is then edited independently. Call inside setState.
  void _goToStep(int step) {
    if (step == 3 && !_recSeeded) {
      _copySide(_leftInit, _leftRec);
      _copySide(_rightInit, _rightRec);
      _recSeeded = true;
    }
    _currentStep = step;
  }

  /// Copy one side's electrode + param state (for seeding recording from
  /// initial). Maps/lists are copied so the two pairs stay independent.
  void _copySide(_SideInputs from, _SideInputs to) {
    to.freq.text = from.freq.text;
    to.amp.text = from.amp.text;
    to.pulseWidth.text = from.pulseWidth.text;
    to.states = Map.of(from.states);
    to.caseState = from.caseState;
    to.enabled = from.enabled;
    to.ampSplit = List.of(from.ampSplit);
  }

  /// Step 1: ONE baseline block (is_initial=1) with the typed clinical
  /// scores, mirroring the desktop write_clinical_scales.
  void _insertBaseline(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits, _leftInit, _rightInit)) return;
    final inserted = _authoring.addInsert(
      isInitial: true,
      stim: _stimCells(catalog, _leftInit, _rightInit),
      scales: [
        for (final s in _clinicalScales)
          (name: s.name.text.trim(), value: s.score.text.trim()),
      ],
      programId: _selectedProgram ?? '',
      electrodeModel: _modelName ?? '',
      notes: _notesInitCtrl.text.trim(),
    );
    // Initial notes are intentionally NOT cleared, so the user can keep
    // refining the initial-config notes without losing earlier text.
    _autosave();
    _snack('Inserted baseline block ${inserted.first.blockId} '
        '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).');
  }

  /// Step 3: one recording block (is_initial=0). Omitted scales write the
  /// contract literal ("NaN"); rated scales write the slider value with the
  /// desktop formatting.
  void _insertRecording(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits, _leftRec, _rightRec)) return;
    final inserted = _authoring.addInsert(
      isInitial: false,
      stim: _stimCells(catalog, _leftRec, _rightRec),
      scales: [
        for (final s in _sessionScales)
          (
            name: s.name.text.trim(),
            value: s.omitted
                ? limits.sessionScaleOmittedTsv
                : _fmtValue(s.value),
          ),
      ],
      programId: _selectedProgram ?? '',
      electrodeModel: _modelName ?? '',
      notes: _notesRecCtrl.text.trim(),
    );
    setState(_notesRecCtrl.clear);
    _autosave();
    _snack('Inserted recording block ${inserted.first.blockId} '
        '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).');
  }

  /// If a save path was chosen (New/Open), rewrite the TSV to it after each
  /// insert (desktop autosaves every entry). No-op when there is no path.
  Future<void> _autosave() async {
    final path = _savePath;
    if (path == null) return;
    try {
      await File(path).writeAsString(_authoring.serialize());
    } catch (e) {
      if (mounted) _snack('Autosave failed: $e');
    }
  }

  // ---- Open / Export (offline pattern from annotations_screen.dart) ----

  Future<void> _newSession() async {
    final subject =
        _subjectCtrl.text.trim().isEmpty ? '01' : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = BidsName(
      subject: subject,
      session: BidsName.sessionStamp(DateTime.now()),
      task: 'programming',
      run: run,
    ).filename;
    // Desktop parity: choose where to create the BIDS TSV before continuing.
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Create new session TSV',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['tsv'],
      );
    } catch (_) {
      // Linux desktop opens native dialogs via zenity/kdialog. If it's absent,
      // fall back to the app documents dir so New still creates the file
      // (a real save dialog appears once zenity is installed, or on a tablet).
      final dir = await getApplicationDocumentsDirectory();
      await Directory(dir.path).create(recursive: true);
      path = '${dir.path}/$name';
      if (mounted) _snack('No file dialog available; saving to $path');
    }
    if (path == null) return; // dialog shown but cancelled
    final p = path.endsWith('.tsv') ? path : '$path.tsv';
    final authoring = SessionAuthoring();
    try {
      await File(p).writeAsString(authoring.serialize()); // header only
    } catch (e) {
      if (mounted) _snack('Could not create $p: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _authoring = authoring;
      _savePath = p;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(p);
      _subjectCtrl.text = subject;
      _runCtrl.text = run;
      _currentStep = 1;
    });
    _snack('New session: $p');
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
        // On Linux desktop this usually means zenity/kdialog is missing.
        _snack('Could not open the file picker. ($e)');
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
    _authoring.loadExisting(content);
    final bids = BidsName.parse(picked.name);
    if (!mounted) return;
    setState(() {
      // Autosave future inserts back to the opened file (when a real path).
      _savePath = picked.path;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(picked.path);
      if (bids != null) {
        _subjectCtrl.text = bids.subject;
        _runCtrl.text = bids.run;
      }
    });
    final opened = 'Opened ${picked.name} (${_authoring.rows.length} rows, '
        'next block ${_authoring.blockId}, session ${_authoring.sessionId}).';
    _snack(_savePathIsSandboxCopy ? '$opened $sandboxCopyNotice' : opened);
  }

  Future<void> _export() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting.');
      return;
    }
    // Context-derived values resolved before the first await.
    final messenger = ScaffoldMessenger.of(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = shareOriginFrom(_exportTsvKey.currentContext);
    final subject = _subjectCtrl.text.trim().isEmpty
        ? 'unknown'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = BidsName(
      subject: subject,
      session: BidsName.sessionStamp(DateTime.now()),
      task: 'programming',
      run: run,
    );
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${name.filename}');
      await file.writeAsString(_authoring.serialize());
      await shareOrSaveFile(messenger, file, name.filename,
          origin: origin, screen: screen);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  /// Build the session-report PDF from the authored rows and share it (mobile)
  /// or save it (desktop). Any failure — e.g. a font that can't render a note
  /// glyph — is surfaced via a snackbar instead of a silent console error.
  Future<void> _exportReport(ElectrodeModel? model) async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting a report.');
      return;
    }
    // Context-derived values resolved before the first await.
    final messenger = ScaffoldMessenger.of(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = shareOriginFrom(_exportReportKey.currentContext);
    final subject = _subjectCtrl.text.trim().isEmpty
        ? 'unknown'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    // Same BIDS-friendly report name as the desktop's
    // _generate_bids_report_filename.
    final stamp = BidsName.sessionStamp(DateTime.now());
    final filename =
        'sub-${subject}_ses-${stamp}_task-programming_run-${run}_report.pdf';
    try {
      final data = buildSessionReportData(rows: _authoring.rows);
      final gfx = await _reportGraphics(data, model);
      final bytes = await buildSessionPdf(
        rows: _authoring.rows,
        subjectId: subject,
        electrodeImages: gfx.electrodes,
        chartPng: gfx.chart,
        pageFormat: _reportLetter ? PdfPageFormat.letter : PdfPageFormat.a4,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await shareOrSaveFile(messenger, file, filename,
          origin: origin, screen: screen);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Report export failed: $e')),
      );
    }
  }

  Future<void> _exportReportDocx(ElectrodeModel? model) async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting a report.');
      return;
    }
    // Context-derived values resolved before the first await.
    final messenger = ScaffoldMessenger.of(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = shareOriginFrom(_exportDocxKey.currentContext);
    final subject = _subjectCtrl.text.trim().isEmpty
        ? 'unknown'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final stamp = BidsName.sessionStamp(DateTime.now());
    final filename =
        'sub-${subject}_ses-${stamp}_task-programming_run-${run}_report.docx';
    try {
      final data = buildSessionReportData(rows: _authoring.rows);
      final gfx = await _reportGraphics(data, model);
      final bytes = buildSessionDocx(
        rows: _authoring.rows,
        subjectId: subject,
        electrodeImages: gfx.electrodes,
        chartPng: gfx.chart,
        pageSize: _reportLetter ? DocxPageSize.letter : DocxPageSize.a4,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await shareOrSaveFile(messenger, file, filename,
          origin: origin, screen: screen);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Report export failed: $e')),
      );
    }
  }

  /// The graphics both report formats embed, rasterised once so the PDF and the
  /// Word document are guaranteed to show identical images.
  Future<({ElectrodeReportImages? electrodes, Uint8List? chart})> _reportGraphics(
      SessionReportData data, ElectrodeModel? model) async {
    final chart = await renderScalesChartPng(data.chart);
    if (model == null) return (electrodes: null, chart: chart);

    // Take the rows report_data itself resolved (highest session, then highest
    // block, numerically coerced). Re-deriving them here with a simpler rule
    // used to let the images show one configuration while the text beside them
    // described another — e.g. for a TSV writing `is_initial` as "1.0".
    Future<Uint8List?> png(SessionRow? row, bool left) async {
      if (row == null) return null;
      return renderElectrodePng(
        model,
        left ? row.leftAnode : row.rightAnode,
        left ? row.leftCathode : row.rightCathode,
      );
    }

    return (
      electrodes: (
        initLeft: await png(data.initialRow, true),
        initRight: await png(data.initialRow, false),
        finalLeft: await png(data.finalRow, true),
        finalRight: await png(data.finalRow, false),
      ),
      chart: chart,
    );
  }

  // ---- Shared UI pieces ----

  List<DropdownMenuItem<String>> _modelItems(ElectrodeCatalog catalog) {
    final items = <DropdownMenuItem<String>>[];
    for (final entry in catalog.manufacturers.entries) {
      items.add(DropdownMenuItem<String>(
        value: null,
        enabled: false,
        child: Text(
          entry.key,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ));
      for (final name in entry.value) {
        items.add(DropdownMenuItem<String>(
          value: name,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(name),
          ),
        ));
      }
    }
    return items;
  }

  /// Desktop three-column org: Params | Electrodes | (scales card + Notes).
  /// Wide/landscape → a Row of the three columns with the Notes field expanding
  /// to fill the remaining height down to the bottom; portrait/narrow → a single
  /// stacked Column with the Notes field at its clamped height.
  Widget _stepBody(Widget params, Widget electrodes, Widget scalesCard,
      TextEditingController notesCtrl) {
    return LayoutBuilder(
      builder: (context, c) {
        final notesColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            scalesCard,
            const SizedBox(height: 12),
            _notesField(notesCtrl),
          ],
        );
        // Wide/landscape → three top-aligned columns; portrait/narrow → stacked.
        // Columns take their natural height (the Stepper scrolls), so nothing
        // overflows on short windows; Notes gets a generous viewport-relative
        // height (see _notesField) rather than a fragile fill-to-bottom.
        if (c.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: params),
              const SizedBox(width: 12),
              Expanded(child: electrodes),
              const SizedBox(width: 12),
              Expanded(child: notesColumn),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            params,
            const SizedBox(height: 12),
            electrodes,
            const SizedBox(height: 12),
            notesColumn,
          ],
        );
      },
    );
  }

  Widget _modelCard(ElectrodeCatalog catalog) {
    return GroupCard(
      title: 'Electrode',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _modelName,
          isExpanded: true,
          isDense: true,
          hint: const Text('Select model'),
          items: _modelItems(catalog),
          onChanged: (name) => setState(() {
            _modelName = name;
            // ElectrodeView resets on model change; mirror in every captured
            // pair (initial + recording, both sides).
            for (final s in [_leftInit, _rightInit, _leftRec, _rightRec]) {
              s.states = {};
              s.caseState = ContactState.off;
            }
          }),
        ),
      ),
    );
  }

  Widget _programCard() {
    final items = _programs;
    final value = items.contains(_selectedProgram) ? _selectedProgram : null;
    return GroupCard(
      title: 'Program',
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: const Text('Select program'),
                items: [
                  for (final p in items)
                    DropdownMenuItem<String>(value: p, child: Text(p)),
                ],
                onChanged: (p) => setState(() => _selectedProgram = p),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Edit programs',
            onPressed: _editPrograms,
          ),
        ],
      ),
    );
  }

  /// Edit + persist the program-name list (desktop program editor).
  Future<void> _editPrograms() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => ListEditorDialog(
        title: 'Programs',
        items: List<String>.of(_programs),
      ),
    );
    if (result == null) return;
    _prefs.programs = result;
    await saveUserPrefs(_prefs);
    if (!mounted) return;
    setState(() {
      if (!result.contains(_selectedProgram)) _selectedProgram = null;
    });
  }

  /// Active cathode labels for [side] (from the encoded cathode string), which
  /// drive the amplitude-split rows.
  List<String> _cathodesFor(_SideInputs side, ElectrodeModel? model) {
    if (model == null) return const [];
    final cathode = encodeTokens(side.states, side.caseState, model).cathode;
    return cathode.split('_').where((t) => t.isNotEmpty && t != 'case').toList();
  }

  /// Column 1 item: one side's stim params + its amplitude split.
  Widget _paramsCard(
      String title, _SideInputs side, ElectrodeModel? model, StimLimits limits) {
    final card = GroupCard(
      title: side.enabled ? title : '$title (off)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StimParamsForm(
            limits: limits,
            frequency: side.freq,
            amplitude: side.amp,
            pulseWidth: side.pulseWidth,
          ),
          // Rebuild only the split when the amplitude controller changes, so
          // the per-cathode mA labels track edits from typing, the steppers,
          // and the preset chips (all mutate side.amp) without rebuilding the
          // heavy electrode canvas.
          ListenableBuilder(
            listenable: side.amp,
            builder: (context, _) => AmplitudeSplit(
              cathodes: _cathodesFor(side, model),
              total: double.tryParse(side.amp.text.trim()) ?? 0,
              decimals: limits.amplitudeDecimals,
              onChanged: (pct) => side.ampSplit = pct,
            ),
          ),
        ],
      ),
    );
    // Deselecting a side's electrode dims its parameters as an "off" hint, but
    // they stay editable (locking input just blocked typing / preset chips).
    return Opacity(opacity: side.enabled ? 1 : 0.6, child: card);
  }

  /// Column 1: model (Step 1 only) + program + Left/Right param groups.
  Widget _paramsColumn(
    ElectrodeCatalog catalog,
    ElectrodeModel? model,
    StimLimits limits, {
    required bool withModel,
    required _SideInputs left,
    required _SideInputs right,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (withModel) ...[_modelCard(catalog), const SizedBox(height: 12)],
        _programCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Parameters',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: 'Edit parameter presets',
              onPressed: () => _editStimPresets(limits),
            ),
          ],
        ),
        _paramsCard('Left', left, model, limits),
        const SizedBox(height: 12),
        _paramsCard('Right', right, model, limits),
      ],
    );
  }

  /// Edit + persist the stimulation quick-pick preset lists via the desktop
  /// "Edit Setting Presets" dialog (3 tabs: Frequency / Amplitude / Pulse
  /// width). Seeded from the effective [limits] presets; saved to [UserPrefs]
  /// so the StimParamsForm chips update live (via withPresets) and persist.
  Future<void> _editStimPresets(StimLimits limits) async {
    final result = await showSettingPresetsDialog(
      context,
      limits: limits,
      frequencies: limits.frequencyPresets,
      amplitudes: limits.amplitudePresets,
      pulseWidths: limits.pulseWidthPresets,
    );
    if (result == null) return;
    setState(() {
      _prefs.stimFrequencies = result.frequencies;
      _prefs.stimAmplitudes = result.amplitudes;
      _prefs.stimPulseWidths = result.pulseWidths;
    });
    await saveUserPrefs(_prefs);
  }

  /// Desktop validation box: green "valid" or a red-bordered "invalid".
  Widget _validationBox(_SideInputs side) {
    final ok = side.validationError.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: ok
          ? null
          : BoxDecoration(
              border: Border.all(color: DbsColors.invalid, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
      child: Text(
        ok ? '✓ Configuration valid' : 'Invalid: ${side.validationError}',
        style: TextStyle(
          color: ok ? DbsColors.valid : DbsColors.invalid,
          fontSize: 12,
        ),
      ),
    );
  }

  /// One electrode pane: enable checkbox + the canvas (dimmed when disabled) +
  /// the validation box.
  Widget _electrodePane(String title, _SideInputs side, ElectrodeModel? model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: side.enabled,
              onChanged: (v) => setState(() => side.enabled = v ?? true),
            ),
            Text(title),
          ],
        ),
        SizedBox(
          // Grow with the window so maximizing enlarges the canvas (and its
          // contacts / ring caps, easing taps); floored for small screens.
          height:
              (MediaQuery.sizeOf(context).height * 0.55).clamp(320.0, 900.0),
          child: model == null
              ? const Center(child: Text('Select an electrode model'))
              : Opacity(
                  opacity: side.enabled ? 1 : 0.3,
                  child: IgnorePointer(
                    ignoring: !side.enabled,
                    child: ElectrodeView(
                      model: model,
                      // Remounted on step switch; seed with captured config.
                      initialStates: side.states,
                      initialCaseState: side.caseState,
                      onChanged: (states, caseState) => setState(() {
                        side.states = states;
                        side.caseState = caseState;
                      }),
                      onValidation: (valid, error) => setState(
                          () => side.validationError = valid ? '' : error),
                    ),
                  ),
                ),
        ),
        _validationBox(side),
      ],
    );
  }

  Widget _legend() {
    Widget swatch(Color base, Color border, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 12,
              decoration:
                  BoxDecoration(color: base, border: Border.all(color: border)),
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 4,
      children: [
        swatch(DbsColors.offBase, DbsColors.offBorder, 'Off'),
        swatch(DbsColors.anodicBase, DbsColors.anodicBorder, 'Anodic (+)'),
        swatch(DbsColors.cathodicBase, DbsColors.cathodicBorder, 'Cathodic (−)'),
      ],
    );
  }

  /// Column 2: the two electrode canvases side by side + legend.
  Widget _electrodesColumn(
      ElectrodeModel? model, _SideInputs left, _SideInputs right) {
    return GroupCard(
      title: 'Electrodes',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _electrodePane('Left', left, model)),
              const SizedBox(width: 8),
              Expanded(child: _electrodePane('Right', right, model)),
            ],
          ),
          const SizedBox(height: 8),
          _legend(),
        ],
      ),
    );
  }

  /// The Notes field, given a generous viewport-relative height so it has real
  /// room. The Stepper scrolls when the column is taller than the window, so
  /// this never overflows on short desktop windows (`expands` needs the bounded
  /// box the SizedBox provides).
  Widget _notesField(TextEditingController notesCtrl) {
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.4).clamp(180.0, 600.0),
      child: TextField(
        controller: notesCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          labelText: 'Notes',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  // ---- Step 0: File ----

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
          _authoring.rows.isEmpty
              ? 'Empty session — the first insert is block 0.'
              : '${_authoring.rows.length} rows loaded; next block '
                  '${_authoring.blockId}, session ${_authoring.sessionId}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ---- Step 1: Initial configuration ----

  /// Replace the clinical rows with a disease preset's scale names, like
  /// the desktop Step-1 pills. If the same disease exists as a session preset,
  /// also pre-select + load it so Step 2 arrives already configured (the user
  /// asked for clinical->session category sync).
  void _applyClinicalPreset(
      String preset, ScalePresets presets, StimLimits limits) {
    setState(() {
      _selectedClinicalPreset = preset;
      _removedClinical.addAll(_clinicalScales);
      _clinicalScales.clear();
      for (final name in clinicalRows(presets, preset)) {
        _clinicalScales.add(_ClinicalScaleEdit()..name.text = name);
      }
      if (presets.session.containsKey(preset)) {
        _loadSessionPresetRows(preset, presets, limits);
      }
    });
  }

  /// Edit + persist the clinical scale presets via the desktop-style group
  /// editor (all disease groups → scale names). [presets] is the effective
  /// (defaults + overrides) set; the result replaces `UserPrefs.clinical` and
  /// is merged live via mergeScalePresets in build().
  Future<void> _editClinicalPresets(ScalePresets presets) async {
    final edited =
        await showClinicalPresetsDialog(context, presets: presets.clinical);
    if (edited == null) return;
    setState(() => _prefs.clinical = edited);
    await saveUserPrefs(_prefs);
    if (mounted) _snack('Clinical scale presets saved.');
  }

  /// Edit + persist the session scale presets via the desktop-style group
  /// editor (all disease groups → (name,min,max) rows; report mode preserved).
  Future<void> _editSessionPresets(ScalePresets presets) async {
    final edited =
        await showSessionPresetsDialog(context, presets: presets.session);
    if (edited == null) return;
    setState(() => _prefs.session = edited);
    await saveUserPrefs(_prefs);
    if (mounted) _snack('Session scale presets saved.');
  }

  /// Disease preset pill styled to match the desktop QSS: amber fill by
  /// default; selected = darker fill + 2px border + bold.
  Widget _presetChip(String preset, bool selected, VoidCallback onTap) {
    // Default = the plain Material chip look; selected = a light accent tint +
    // a bolder accent border + bold label (no full amber fill).
    return ChoiceChip(
      label: Text(preset),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: DbsColors.accent.withValues(alpha: 0.2),
      side: selected
          ? const BorderSide(color: DbsColors.accent, width: 2)
          : null,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _clinicalScalesCard(ScalePresets presets, StimLimits limits) {
    return Card(
      // Warm fill + outline to match GroupCard (dark-safe; no M3 blue).
      color: DbsColors.cardFill(Theme.of(context).brightness == Brightness.dark),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Clinical scales',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings clinical scales',
                  onPressed: () => _editClinicalPresets(presets),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add clinical scale',
                  onPressed: () => setState(
                      () => _clinicalScales.add(_ClinicalScaleEdit())),
                ),
              ],
            ),
            if (presets.buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // Desktop disease pills: tapping one REPLACES the rows with
                // that preset's clinical scale names.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets.buttons)
                      _presetChip(
                        preset,
                        _selectedClinicalPreset == preset,
                        () => _applyClinicalPreset(preset, presets, limits),
                      ),
                  ],
                ),
              ),
            for (final scale in _clinicalScales)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: scale.name,
                      decoration: const InputDecoration(
                        labelText: 'Scale name',
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: TextField(
                        controller: scale.score,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Score',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove clinical scale',
                    onPressed: () => setState(() {
                      _clinicalScales.remove(scale);
                      _removedClinical.add(scale);
                    }),
                  ),
                ],
              ),
            if (_clinicalScales.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('No scales — the insert writes one scale-less '
                    'row (like the desktop).'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initialStep(
    ElectrodeCatalog catalog,
    StimLimits limits,
    ScalePresets presets,
    ElectrodeModel? model,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBody(
          _paramsColumn(catalog, model, limits,
              withModel: true, left: _leftInit, right: _rightInit),
          _electrodesColumn(model, _leftInit, _rightInit),
          _clinicalScalesCard(presets, limits),
          _notesInitCtrl,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _insertBaseline(catalog, limits),
          icon: const Icon(Icons.add),
          label: const Text('Insert baseline'),
        ),
      ],
    );
  }

  // ---- Step 2: Session scales (definition only, no TSV write) ----

  /// Replace the session scale set with a disease preset's (name, min, max)
  /// rows, like the desktop Step-2 pills.
  void _applySessionPreset(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    setState(() => _loadSessionPresetRows(preset, presets, limits));
  }

  /// Mutating helper (call inside a setState): swap the session scale set to a
  /// preset's rows. Shared by the Step-2 pills and the clinical->session sync.
  void _loadSessionPresetRows(
      String preset, ScalePresets presets, StimLimits limits) {
    final fallback = limits.sessionScale;
    _selectedSessionPreset = preset;
    _removedSession.addAll(_sessionScales);
    _sessionScales.clear();
    for (final row in sessionRows(presets, preset)) {
      _sessionScales.add(_SessionScaleEdit(
        min: double.tryParse(row.min) ?? fallback.min,
        max: double.tryParse(row.max) ?? fallback.max,
        name: row.name,
      ));
    }
  }

  Widget _scalesStep(StimLimits limits, ScalePresets presets) {
    final range = limits.sessionScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Session scales configuration',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings session scales',
              onPressed: () => _editSessionPresets(presets),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add session scale',
              onPressed: () => setState(() => _sessionScales.add(
                  _SessionScaleEdit(min: range.min, max: range.max))),
            ),
          ],
        ),
        if (presets.buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Desktop disease pills: tapping one REPLACES the set with that
            // preset's (name, min, max) rows.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets.buttons)
                  _presetChip(
                    preset,
                    _selectedSessionPreset == preset,
                    () => _applySessionPreset(preset, presets, limits),
                  ),
              ],
            ),
          ),
        for (final scale in _sessionScales)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: scale.name,
                  decoration: const InputDecoration(
                    labelText: 'Scale name',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: scale.minCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: scale.maxCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove session scale',
                onPressed: () => setState(() {
                  _sessionScales.remove(scale);
                  _removedSession.add(scale);
                }),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _sessionScales.isEmpty
                ? 'No session scales — recording inserts write one '
                    'scale-less row (like the desktop).'
                : 'These scales are rated in the Recording step; nothing is '
                    'written to the TSV here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  // ---- Step 3: Recording ----

  /// One rating row: name, 0.5-step slider bounded by the Step-2 min/max,
  /// current value, and the omit ("not assessed") switch. Omitted rows are
  /// written as the contract literal ("NaN").
  Widget _ratingRow(_SessionScaleEdit scale, StimLimits limits) {
    final min = scale.minOr(limits.sessionScale.min);
    var max = scale.maxOr(limits.sessionScale.max);
    if (max <= min) max = min + 1;
    final name = scale.name.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(name.isEmpty ? '(unnamed scale)' : name),
          ),
          Expanded(
            flex: 5,
            // Desktop ScaleProgressWidget: bar + value + ±0.25/±0.5 chevrons +
            // X-omit. Any move re-includes an omitted scale.
            child: ScaleSlider(
              value: scale.value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              omitted: scale.omitted,
              onChanged: (v) => setState(() {
                scale.value = v;
                scale.omitted = false;
              }),
              onOmitToggle: () =>
                  setState(() => scale.omitted = !scale.omitted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingsCard(StimLimits limits) {
    return Card(
      // Warm fill + outline to match GroupCard (dark-safe; no M3 blue).
      color: DbsColors.cardFill(Theme.of(context).brightness == Brightness.dark),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Session scale ratings',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_sessionScales.isEmpty)
              const Text('No session scales defined — add them in the '
                  'Session scales step.')
            else
              for (final scale in _sessionScales) _ratingRow(scale, limits),
          ],
        ),
      ),
    );
  }

  /// Review table of every inserted TSV row (one row per scale), so the user
  /// can check what has been recorded instead of only the transient snackbars.
  Widget _blocksList() {
    final rows = _authoring.rows;
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('No entries inserted yet.')),
      );
    }
    String triple(String f, String a, String pw) =>
        [f, a, pw].map((s) => s.trim().isEmpty ? '–' : s.trim()).join(' / ');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 72,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('Blk')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Prog')),
          DataColumn(label: Text('Scale')),
          DataColumn(label: Text('Value')),
          DataColumn(label: Text('L  Hz/mA/µs')),
          DataColumn(label: Text('R  Hz/mA/µs')),
          DataColumn(label: Text('Notes')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(r.blockId)),
              DataCell(Text(r.isInitial == '1' ? 'Initial' : 'Rec')),
              DataCell(Text('${r.date} ${r.time}')),
              DataCell(Text(r.programId)),
              DataCell(Text(r.scaleName)),
              DataCell(Text(r.scaleValue)),
              DataCell(Text(
                  triple(r.leftStimFreq, r.leftAmplitude, r.leftPulseWidth))),
              DataCell(Text(triple(
                  r.rightStimFreq, r.rightAmplitude, r.rightPulseWidth))),
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(r.notes,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              )),
            ]),
        ],
      ),
    );
  }

  Widget _recordingStep(
    ElectrodeCatalog catalog,
    StimLimits limits,
    ElectrodeModel? model,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBody(
          _paramsColumn(catalog, model, limits,
              withModel: false, left: _leftRec, right: _rightRec),
          _electrodesColumn(model, _leftRec, _rightRec),
          _ratingsCard(limits),
          _notesRecCtrl,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _insertRecording(catalog, limits),
          icon: const Icon(Icons.add),
          label: const Text('Insert recording block'),
        ),
        const SizedBox(height: 8),
        if (_savePathIsSandboxCopy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              sandboxCopyNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: _exportTsvKey,
              onPressed: _export,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export TSV'),
            ),
            OutlinedButton.icon(
              key: _exportReportKey,
              onPressed: () => _exportReport(model),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export report (PDF)'),
            ),
            OutlinedButton.icon(
              key: _exportDocxKey,
              onPressed: () => _exportReportDocx(model),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Export report (Word)'),
            ),
            // Paper size for both report formats, persisted per user.
            Tooltip(
              message: 'Paper size for exported reports',
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: 'a4', label: Text('A4')),
                  ButtonSegment(value: 'letter', label: Text('Letter')),
                ],
                selected: {_prefs.reportPageSize ?? kDefaultReportPageSize},
                onSelectionChanged: (sel) {
                  setState(() => _prefs.reportPageSize = sel.first);
                  saveUserPrefs(_prefs);
                },
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Inserted entries (session ${_authoring.sessionId})',
            style: Theme.of(context).textTheme.titleMedium),
        _blocksList(),
      ],
    );
  }

  // ---- Wizard scaffold ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete workflow'),
        actions: const [
          TextSizeButtons(),
          HelpButton(),
          ThemeToggleButton()
        ],
      ),
      body: FutureBuilder<(ElectrodeCatalog, StimLimits, ScalePresets)>(
        future: _contracts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load schema contracts: '
                    '${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (catalog, rawLimits, rawPresets) = snapshot.data!;
          // Layer the user's saved overrides (F7) over the bundled contract so
          // edited presets show immediately and survive relaunch.
          final limits = rawLimits.withPresets(
            frequencies: _prefs.stimFrequencies,
            amplitudes: _prefs.stimAmplitudes,
            pulseWidths: _prefs.stimPulseWidths,
          );
          final presets = mergeScalePresets(rawPresets, _prefs);
          final model =
              _modelName == null ? null : catalog.models[_modelName];
          // Only the active step builds its (heavy) content: keeps one
          // ElectrodeView / one Notes field per side in the tree at a time,
          // so state lives in _SessionScreenState, not in step widgets.
          Widget when(int step, Widget Function() builder) =>
              _currentStep == step ? builder() : const SizedBox.shrink();
          return Stepper(
            currentStep: _currentStep,
            onStepTapped: (i) => setState(() => _goToStep(i)),
            onStepContinue: _currentStep < 3
                ? () => setState(() => _goToStep(_currentStep + 1))
                : null,
            onStepCancel: _currentStep > 0
                ? () => setState(() => _currentStep -= 1)
                : null,
            controlsBuilder: (context, details) {
              if (details.stepIndex != _currentStep) {
                return const SizedBox.shrink();
              }
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
                content: when(0, _fileStep),
              ),
              Step(
                title: const Text('Initial configuration'),
                subtitle: const Text(
                    'Baseline stimulation + clinical scales (is_initial 1)'),
                isActive: _currentStep == 1,
                content:
                    when(1, () => _initialStep(catalog, limits, presets, model)),
              ),
              Step(
                title: const Text('Session scales configuration'),
                subtitle:
                    const Text('Define the scale set rated during recording'),
                isActive: _currentStep == 2,
                content: when(2, () => _scalesStep(limits, presets)),
              ),
              Step(
                title: const Text('Recording'),
                subtitle: const Text(
                    'Stimulation + ratings (is_initial 0), export'),
                isActive: _currentStep == 3,
                content: when(3, () => _recordingStep(catalog, limits, model)),
              ),
            ],
          );
        },
      ),
    );
  }
}
