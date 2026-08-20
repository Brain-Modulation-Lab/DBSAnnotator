/// One row of a programming-session (`task-programming`) TSV.
///
/// Mirrors the desktop writer in
/// src/dbs_annotator/models/session_data.py (write_clinical_scales /
/// write_session_scales). Every field is kept as the raw TSV string so a
/// parse -> serialize round trip is lossless (the desktop may write block
/// IDs as "3" or "3.0", amplitudes as split strings like "1.5_1", and
/// scale_name/scale_value cells with embedded newlines).
class SessionRow {
  const SessionRow({
    this.date = '',
    this.time = '',
    this.timezone = '',
    this.blockId = '',
    this.sessionId = '',
    this.isInitial = '',
    this.scaleName = '',
    this.scaleValue = '',
    this.electrodeModel = '',
    this.programId = '',
    this.leftStimFreq = '',
    this.leftAnode = '',
    this.leftCathode = '',
    this.leftAmplitude = '',
    this.leftPulseWidth = '',
    this.rightStimFreq = '',
    this.rightAnode = '',
    this.rightCathode = '',
    this.rightAmplitude = '',
    this.rightPulseWidth = '',
    this.notes = '',
  });

  final String date;
  final String time;
  final String timezone;
  final String blockId;
  final String sessionId;
  final String isInitial;
  final String scaleName;
  final String scaleValue;
  final String electrodeModel;
  final String programId;
  final String leftStimFreq;
  final String leftAnode;
  final String leftCathode;
  final String leftAmplitude;
  final String leftPulseWidth;
  final String rightStimFreq;
  final String rightAnode;
  final String rightCathode;
  final String rightAmplitude;
  final String rightPulseWidth;
  final String notes;

  /// Build from a TSV record keyed by the exact column names in
  /// schema_columns.dart `sessionColumns`. Missing columns become ''.
  factory SessionRow.fromMap(Map<String, String> m) => SessionRow(
        date: m['date'] ?? '',
        time: m['time'] ?? '',
        timezone: m['timezone'] ?? '',
        blockId: m['block_ID'] ?? '',
        sessionId: m['session_ID'] ?? '',
        isInitial: m['is_initial'] ?? '',
        scaleName: m['scale_name'] ?? '',
        scaleValue: m['scale_value'] ?? '',
        electrodeModel: m['electrode_model'] ?? '',
        programId: m['program_ID'] ?? '',
        leftStimFreq: m['left_stim_freq'] ?? '',
        leftAnode: m['left_anode'] ?? '',
        leftCathode: m['left_cathode'] ?? '',
        leftAmplitude: m['left_amplitude'] ?? '',
        leftPulseWidth: m['left_pulse_width'] ?? '',
        rightStimFreq: m['right_stim_freq'] ?? '',
        rightAnode: m['right_anode'] ?? '',
        rightCathode: m['right_cathode'] ?? '',
        rightAmplitude: m['right_amplitude'] ?? '',
        rightPulseWidth: m['right_pulse_width'] ?? '',
        notes: m['notes'] ?? '',
      );

  /// Convert to a TSV record keyed by the exact column names.
  Map<String, String> toMap() => {
        'date': date,
        'time': time,
        'timezone': timezone,
        'block_ID': blockId,
        'session_ID': sessionId,
        'is_initial': isInitial,
        'scale_name': scaleName,
        'scale_value': scaleValue,
        'electrode_model': electrodeModel,
        'program_ID': programId,
        'left_stim_freq': leftStimFreq,
        'left_anode': leftAnode,
        'left_cathode': leftCathode,
        'left_amplitude': leftAmplitude,
        'left_pulse_width': leftPulseWidth,
        'right_stim_freq': rightStimFreq,
        'right_anode': rightAnode,
        'right_cathode': rightCathode,
        'right_amplitude': rightAmplitude,
        'right_pulse_width': rightPulseWidth,
        'notes': notes,
      };
}
