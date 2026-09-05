class TomSystemModel {
  final String id;
  final String stationId;
  final String systemName;
  final String systemType;
  final bool isActive;

  TomSystemModel({
    required this.id,
    required this.stationId,
    required this.systemName,
    this.systemType = 'TOM',
    this.isActive = true,
  });

  factory TomSystemModel.fromMap(Map<String, dynamic> map) {
    return TomSystemModel(
      id: map['id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      systemName: map['system_name']?.toString() ?? 'TOM Counter',
      systemType: map['system_type']?.toString() ?? 'TOM',
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'station_id': stationId,
      'system_name': systemName,
      'system_type': systemType,
      'is_active': isActive,
    };
  }
}
