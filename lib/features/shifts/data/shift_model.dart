class ShiftAssignmentModel {
  final String id;
  final String shiftId;
  final String stationId;
  final String operatingSystemId;
  final String systemName;
  final String operatorId;
  final String operatorName;
  final bool isOt;

  const ShiftAssignmentModel({
    required this.id,
    required this.shiftId,
    required this.stationId,
    required this.operatingSystemId,
    required this.systemName,
    required this.operatorId,
    required this.operatorName,
    this.isOt = false,
  });

  factory ShiftAssignmentModel.fromMap(Map<String, dynamic> map) {
    final profileData = map['profiles'] as Map<String, dynamic>?;
    final osData = map['operating_systems'] as Map<String, dynamic>?;

    return ShiftAssignmentModel(
      id: map['id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      operatingSystemId:
          (map['operating_system_id'] ?? map['system_id'])?.toString() ?? '',
      systemName: osData?['system_name'] ?? map['system_name'] ?? 'TOM Counter',
      operatorId: map['operator_id']?.toString() ?? '',
      operatorName:
          profileData?['full_name'] ??
          map['operator_name'] ??
          'Assigned Operator',
      isOt: map['is_ot'] as bool? ?? false,
    );
  }
}

class ShiftModel {
  final String id;
  final String orgId;
  final String stationId;
  final String stationName;
  final String shiftName;
  final String dutyDate;
  final String startTime;
  final String endTime;
  final double dailyAmount;
  final bool isPublished;
  final List<ShiftAssignmentModel> assignments;

  const ShiftModel({
    required this.id,
    required this.orgId,
    required this.stationId,
    required this.stationName,
    required this.shiftName,
    required this.dutyDate,
    required this.startTime,
    required this.endTime,
    required this.dailyAmount,
    this.isPublished = false,
    this.assignments = const [],
  });

  factory ShiftModel.fromMap(
    Map<String, dynamic> map, {
    List<ShiftAssignmentModel> assignments = const [],
  }) {
    return ShiftModel(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      stationId: map['station_id'] as String,
      stationName: map['stations']?['name'] ?? 'Station',
      shiftName: map['shift_name'] as String,
      dutyDate: map['duty_date'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      dailyAmount: (map['daily_amount'] as num?)?.toDouble() ?? 700.00,
      isPublished: map['is_published'] as bool? ?? false,
      assignments: assignments,
    );
  }
}
