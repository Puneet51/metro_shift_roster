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
      shiftName:
          map['shift_name']?.toString() ?? map['name']?.toString() ?? 'A Shift',
      startTime: map['start_time']?.toString() ?? map['start']?.toString() ?? '06:00:00',
      endTime: map['end_time']?.toString() ?? map['end']?.toString() ?? '14:00:00',
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
      isDefault: map['is_active'] != null ? (map['is_active'] as bool) : true,
    );
  }
}

class StationModel {
  final String id;
  final String orgId;
  final String name;
  final String code;
  final double latitude;
  final double longitude;
  final double defaultFixedAmount;
  final List<StationOperatingSystemModel> operatingSystems;
  final List<StationShiftTemplate> shiftTemplates;

  const StationModel({
    required this.id,
    required this.orgId,
    required this.name,
    this.code = '',
    required this.latitude,
    required this.longitude,
    required this.defaultFixedAmount,
    this.operatingSystems = const [],
    this.shiftTemplates = const [],
  });

  factory StationModel.fromMap(Map<String, dynamic> map) {
    // 1. Parse TOM systems from the PostgREST joined relation
    List<StationOperatingSystemModel> ops = [];
    if (map['station_operating_systems'] is List) {
      ops = (map['station_operating_systems'] as List)
          .map(
            (item) => StationOperatingSystemModel.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    }

    // 2. Parse Shift Templates from the JSONB column or child relation
    List<StationShiftTemplate> shifts = [];
    if (map['shift_templates'] is List) {
      shifts = (map['shift_templates'] as List)
          .map(
            (item) => StationShiftTemplate.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    }

    return StationModel(
      id: map['id']?.toString() ?? '',
      orgId: map['org_id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Station',
      code: map['code']?.toString() ?? '',
      latitude: double.tryParse(map['latitude']?.toString() ?? '') ?? 0.0,
      longitude: double.tryParse(map['longitude']?.toString() ?? '') ?? 0.0,
      defaultFixedAmount:
          double.tryParse(map['default_fixed_amount']?.toString() ?? '') ??
          700.0,
      operatingSystems: ops,
      shiftTemplates: shifts,
    );
  }
}
