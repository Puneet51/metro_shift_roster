class PunchSessionModel {
  final String id;
  final String operatorId;
  final String? stationId;
  final String? stationName;
  final String dutyDate;
  final DateTime punchInAt;
  final DateTime? punchOutAt;
  final String
      status; // 'in_progress', 'completed', 'unassigned_pending', 'rejected', 'auto_absent'

  const PunchSessionModel({
    required this.id,
    required this.operatorId,
    this.stationId,
    this.stationName,
    required this.dutyDate,
    required this.punchInAt,
    this.punchOutAt,
    required this.status,
  });

  factory PunchSessionModel.fromMap(Map<String, dynamic> map) {
    return PunchSessionModel(
      id: map['id'] as String,
      operatorId: map['operator_id'] as String,
      stationId: map['station_id'] as String?,
      stationName: map['stations']?['name'] as String?,
      dutyDate: map['duty_date'] as String,
      punchInAt: DateTime.parse(map['punch_in_at'] as String),
      punchOutAt: map['punch_out_at'] != null
          ? DateTime.parse(map['punch_out_at'] as String)
          : null,
      status: map['status'] as String,
    );
  }
}

class AttendanceSummaryModel {
  final int totalDuty;
  final double earnings;
  final int otDutyCount;
  final int weekOffCount;

  const AttendanceSummaryModel({
    this.totalDuty = 0,
    this.earnings = 0.0,
    this.otDutyCount = 0,
    this.weekOffCount = 0,
  });
}
