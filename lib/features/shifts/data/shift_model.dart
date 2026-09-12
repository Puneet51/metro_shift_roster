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
    final profileData = map['profiles'] is Map
        ? map['profiles'] as Map<String, dynamic>
        : null;

    // Check both potential joined table aliases for operating system
    final osData = (map['station_operating_systems'] is Map)
        ? map['station_operating_systems'] as Map<String, dynamic>
        : (map['operating_systems'] is Map
              ? map['operating_systems'] as Map<String, dynamic>
              : null);

    return ShiftAssignmentModel(
      id: map['id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      operatingSystemId:
          (map['operating_system_id'] ?? map['system_id'])?.toString() ?? '',
      systemName:
          osData?['system_name']?.toString() ??
          map['system_name']?.toString() ??
          'TOM 01',
      operatorId: map['operator_id']?.toString() ?? '',
      operatorName:
          profileData?['full_name']?.toString() ??
          map['operator_name']?.toString() ??
          '',
      isOt: map['is_ot'] == true,
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
  final String? templateId;
  final String startTime;
  final String endTime;
  final double dailyAmount;
  final bool isPublished;
  final String? publishedByName;
  final List<ShiftAssignmentModel> assignments;

  const ShiftModel({
    required this.id,
    required this.orgId,
    required this.stationId,
    required this.stationName,
    required this.shiftName,
    required this.dutyDate,
    this.templateId,
    required this.startTime,
    required this.endTime,
    required this.dailyAmount,
    this.isPublished = false,
    this.publishedByName,
    this.assignments = const [],
  });

  factory ShiftModel.fromMap(
    Map<String, dynamic> map, {
    List<ShiftAssignmentModel>? assignments,
  }) {
    final stationData = map['stations'] is Map
        ? map['stations'] as Map<String, dynamic>
        : null;

    // Automatically parse nested shift_assignments if present in the map
    List<ShiftAssignmentModel> resolvedAssignments = assignments ?? [];
    if (resolvedAssignments.isEmpty && map['shift_assignments'] is List) {
      resolvedAssignments = (map['shift_assignments'] as List)
          .whereType<Map>()
          .map(
            (item) =>
                ShiftAssignmentModel.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    }

    return ShiftModel(
      id: map['id']?.toString() ?? '',
      orgId: map['org_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      stationName:
          stationData?['name']?.toString() ??
          map['station_name']?.toString() ??
          'Station',
      shiftName: map['shift_name']?.toString() ?? '',
      dutyDate: map['duty_date']?.toString() ?? '',
      templateId: map['template_id']?.toString(),
      startTime: map['start_time']?.toString() ?? '',
      endTime: map['end_time']?.toString() ?? '',
      dailyAmount: (map['daily_amount'] as num?)?.toDouble() ?? 700.00,
      isPublished: map['is_published'] == true,
      publishedByName: map['published_by_name']?.toString(),
      assignments: resolvedAssignments,
    );
  }
}
