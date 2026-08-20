import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/bids.dart';
import '../core/electrode/amplitude.dart';
import '../core/electrode/contact_state.dart';
import '../core/electrode/electrode_model.dart';
import '../core/electrode/stimulation_rule.dart';
import '../core/electrode/tokens.dart';
import '../core/prefs/user_prefs.dart';
import '../core/session/authoring.dart';
import '../core/session/scale_presets.dart';
import '../report/session_pdf.dart';
import '../app_info.dart';
import 'amplitude_split.dart';
import 'electrode_view.dart';
import 'list_editor_dialog.dart';
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
  final _notesCtrl = TextEditingController();
  final _left = _SideInputs();
  final _right = _SideInputs();
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
    _notesCtrl.dispose();
    _left.dispose();
    _right.dispose();
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
  bool _stimInRange(StimLimits limits) {
    final outOfRange = [
      rangeError(_left.freq.text, limits.frequency),
      rangeError(_left.amp.text, limits.amplitude),
      rangeError(_left.pulseWidth.text, limits.pulseWidth),
      rangeError(_right.freq.text, limits.frequency),
      rangeError(_right.amp.text, limits.amplitude),
      rangeError(_right.pulseWidth.text, limits.pulseWidth),
    ].whereType<String>();
    if (outOfRange.isNotEmpty) {
      _snack('Fix out-of-range stimulation values before inserting.');
      return false;
    }
    return true;
  }

  /// The 10 stimulation TSV cells from the current L/R inputs.
  Map<String, String> _stimCells(ElectrodeCatalog catalog) {
    final model = _modelName == null ? null : catalog.models[_modelName];
    var leftTokens = (anode: '', cathode: '');
    var rightTokens = (anode: '', cathode: '');
    if (model != null) {
      leftTokens = encodeTokens(_left.states, _left.caseState, model);
      rightTokens = encodeTokens(_right.states, _right.caseState, model);
    }
    return {
      'left_stim_freq': _left.freq.text.trim(),
      'left_anode': leftTokens.anode,
      'left_cathode': leftTokens.cathode,
      'left_amplitude': _amplitudeFor(_left, leftTokens),
      'left_pulse_width': _left.pulseWidth.text.trim(),
      'right_stim_freq': _right.freq.text.trim(),
      'right_anode': rightTokens.anode,
      'right_cathode': rightTokens.cathode,
      'right_amplitude': _amplitudeFor(_right, rightTokens),
      'right_pulse_width': _right.pulseWidth.text.trim(),
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

  /// Step 1: ONE baseline block (is_initial=1) with the typed clinical
  /// scores, mirroring the desktop write_clinical_scales.
  void _insertBaseline(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits)) return;
    final inserted = _authoring.addInsert(
      isInitial: true,
      stim: _stimCells(catalog),
      scales: [
        for (final s in _clinicalScales)
          (name: s.name.text.trim(), value: s.score.text.trim()),
      ],
      programId: _selectedProgram ?? '',
      electrodeModel: _modelName ?? '',
      notes: _notesCtrl.text.trim(),
    );
    setState(_notesCtrl.clear);
    _autosave();
    _snack('Inserted baseline block ${inserted.first.blockId} '
        '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).');
  }

  /// Step 3: one recording block (is_initial=0). Omitted scales write the
  /// contract literal ("NaN"); rated scales write the slider value with the
  /// desktop formatting.
  void _insertRecording(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits)) return;
    final inserted = _authoring.addInsert(
      isInitial: false,
      stim: _stimCells(catalog),
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
      notes: _notesCtrl.text.trim(),
    );
    setState(_notesCtrl.clear);
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
    // Resolved before the first await, like the messenger in _shareOrSave.
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

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${name.filename}');
    await file.writeAsString(_authoring.serialize());

    await _shareOrSave(file, name.filename, origin);
  }

  /// Share (mobile) or, on desktop where share_plus has no share sheet, save to
  /// Documents. See [shareOrSaveFile]. [origin] anchors the iPadOS popover and
  /// must be resolved by the caller before its first await.
  Future<void> _shareOrSave(File tempFile, String filename, Rect? origin) =>
      shareOrSaveFile(
        ScaffoldMessenger.of(context),
        tempFile,
        filename,
        origin: origin,
      );

  /// Build the session-report PDF from the authored rows and hand it to the
  /// OS share sheet (same offline pattern as the TSV export, which stays
  /// available alongside this).
  Future<void> _exportReport() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting a report.');
      return;
    }
    // Resolved before the first await, like the messenger in _shareOrSave.
    final origin = shareOriginFrom(_exportReportKey.currentContext);
    final subject = _subjectCtrl.text.trim().isEmpty
        ? 'unknown'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final bytes = await buildSessionPdf(
      rows: _authoring.rows,
      subjectId: subject,
    );

    // Same BIDS-friendly report name as the desktop's
    // _generate_bids_report_filename.
    final stamp = BidsName.sessionStamp(DateTime.now());
    final filename =
        'sub-${subject}_ses-${stamp}_task-programming_run-${run}_report.pdf';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    await _shareOrSave(file, filename, origin);
  }

  // ---- Shared UI pieces ----

  /// One summary entry per block, derived from the authoring rows.
  List<({String block, String isInitial, String time, int rowCount})>
      _blockSummaries() {
    final out =
        <({String block, String isInitial, String time, int rowCount})>[];
    for (final row in _authoring.rows) {
      if (out.isNotEmpty && out.last.block == row.blockId) {
        final last = out.removeLast();
        out.add((
          block: last.block,
          isInitial: last.isInitial,
          time: last.time,
          rowCount: last.rowCount + 1,
        ));
      } else {
        out.add((
          block: row.blockId,
          isInitial: row.isInitial,
          time: '${row.date} ${row.time}',
          rowCount: 1,
        ));
      }
    }
    return out;
  }

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
  Widget _stepBody(Widget params, Widget electrodes, Widget scalesCard) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 900) {
          // Bound the row so `stretch` + `Expanded` have a definite height (the
          // Stepper otherwise hands unbounded height). Params/electrodes scroll
          // if taller; the scales column's Notes fills the leftover space.
          final rowH =
              (MediaQuery.sizeOf(context).height * 0.7).clamp(360.0, 1000.0);
          return SizedBox(
            height: rowH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SingleChildScrollView(child: params)),
                const SizedBox(width: 12),
                Expanded(child: SingleChildScrollView(child: electrodes)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      scalesCard,
                      const SizedBox(height: 12),
                      Expanded(child: _notesField(expand: true)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            params,
            const SizedBox(height: 12),
            electrodes,
            const SizedBox(height: 12),
            scalesCard,
            const SizedBox(height: 12),
            _notesField(),
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
            // ElectrodeView resets on model change; mirror in captured state.
            _left.states = {};
            _left.caseState = ContactState.off;
            _right.states = {};
            _right.caseState = ContactState.off;
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
    // Deselecting a side's electrode also turns its parameters "off" (desktop
    // dims + disables the whole side).
    return Opacity(
      opacity: side.enabled ? 1 : 0.3,
      child: IgnorePointer(ignoring: !side.enabled, child: card),
    );
  }

  /// Column 1: model (Step 1 only) + program + Left/Right param groups.
  Widget _paramsColumn(
    ElectrodeCatalog catalog,
    ElectrodeModel? model,
    StimLimits limits, {
    required bool withModel,
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
        _paramsCard('Left', _left, model, limits),
        const SizedBox(height: 12),
        _paramsCard('Right', _right, model, limits),
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
  Widget _electrodesColumn(ElectrodeModel? model) {
    return GroupCard(
      title: 'Electrodes',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _electrodePane('Left', _left, model)),
              const SizedBox(width: 8),
              Expanded(child: _electrodePane('Right', _right, model)),
            ],
          ),
          const SizedBox(height: 8),
          _legend(),
        ],
      ),
    );
  }

  /// The Notes field. When [expand] the caller wraps it in an `Expanded`
  /// (inside the bounded landscape row), so it fills to the bottom; otherwise
  /// (portrait/stacked, where the Stepper gives unbounded height) it takes a
  /// viewport-clamped fixed height — `expands` needs a bounded box either way.
  Widget _notesField({bool expand = false}) {
    final textField = TextField(
      controller: _notesCtrl,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        labelText: 'Notes',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
    if (expand) return textField;
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.25).clamp(120.0, 400.0),
      child: textField,
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
          _paramsColumn(catalog, model, limits, withModel: true),
          _electrodesColumn(model),
          _clinicalScalesCard(presets, limits),
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

  Widget _blocksList() {
    final blocks = _blockSummaries();
    if (blocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('No blocks inserted yet.')),
      );
    }
    return Column(
      children: [
        for (final b in blocks.reversed)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 16, child: Text(b.block)),
            title: Text(b.isInitial == '1'
                ? 'Baseline (initial)'
                : 'Recording block'),
            subtitle: Text(
                '${b.time} — ${b.rowCount} row${b.rowCount == 1 ? '' : 's'}'),
          ),
      ],
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
          _paramsColumn(catalog, model, limits, withModel: false),
          _electrodesColumn(model),
          _ratingsCard(limits),
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
        Row(
          children: [
            OutlinedButton.icon(
              key: _exportTsvKey,
              onPressed: _export,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export TSV'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: _exportReportKey,
              onPressed: _exportReport,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export report (PDF)'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Inserted blocks (session ${_authoring.sessionId})',
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
            onStepTapped: (i) => setState(() => _currentStep = i),
            onStepContinue: _currentStep < 3
                ? () => setState(() => _currentStep += 1)
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
