class StationShiftTemplate {
  final String id;
  final String stationId;
  final String shiftName;
  final String startTime;
  final String endTime;

  const StationShiftTemplate({
    required this.id,
    required this.stationId,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
  });

  factory StationShiftTemplate.fromMap(Map<String, dynamic> map) {
    return StationShiftTemplate(
      id: map['id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      shiftName: map['shift_name']?.toString() ?? 'A Shift',
      startTime: map['start_time']?.toString() ?? '06:00:00',
      endTime: map['end_time']?.toString() ?? '14:00:00',
    );
  }
}

class StationOperatingSystemModel {
  final String id;
  final String stationId;
  final String systemName;
  final bool isDefault;

  const StationOperatingSystemModel({
    required this.id,
    required this.stationId,
    required this.systemName,
    this.isDefault = true,
  });

  factory StationOperatingSystemModel.fromMap(Map<String, dynamic> map) {
    return StationOperatingSystemModel(
      id: map['id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      systemName: map['system_name']?.toString() ?? 'TOM 01',
      isDefault: map['is_default'] != null ? (map['is_default'] as bool) : true,
    );
  }
}

class StationModel {
  final String id;
  final String orgId;
  final String name;
  final double latitude;
  final double longitude;
  final int punchRadiusMeters;
  final double defaultFixedAmount;
  final List<StationOperatingSystemModel> operatingSystems;
  final List<StationShiftTemplate> shiftTemplates;

  const StationModel({
    required this.id,
    required this.orgId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.punchRadiusMeters,
    required this.defaultFixedAmount,
    this.operatingSystems = const [],
    this.shiftTemplates = const [],
  });

  factory StationModel.fromMap(
    Map<String, dynamic> map, {
    List<StationOperatingSystemModel> operatingSystems = const [],
    List<StationShiftTemplate> shiftTemplates = const [],
  }) {
    return StationModel(
      id: map['id']?.toString() ?? '',
      orgId: map['org_id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Station',
      latitude: double.tryParse(map['latitude']?.toString() ?? '') ?? 0.0,
      longitude: double.tryParse(map['longitude']?.toString() ?? '') ?? 0.0,
      punchRadiusMeters:
          int.tryParse(map['punch_radius_meters']?.toString() ?? '') ?? 600,
      defaultFixedAmount:
          double.tryParse(map['default_fixed_amount']?.toString() ?? '') ??
              700.0,
      operatingSystems: operatingSystems,
      shiftTemplates: shiftTemplates,
    );
  }
}
