import 'package:supabase_flutter/supabase_flutter.dart';
import 'station_model.dart';

class StationRepository {
  final SupabaseClient _client;

  StationRepository(this._client);

  /// Fetch all stations for the entire organization
  Future<List<StationModel>> getStations(String orgId) async {
    final response = await _client
        .from('stations')
        .select('*, station_operating_systems(*), station_shift_templates(*)')
        .eq('org_id', orgId)
        .order('name', ascending: true);

    final List<StationModel> stations = [];

    for (final item in response as List) {
      final s = item as Map<String, dynamic>;
      final rawSystems = s['station_operating_systems'] as List? ?? [];
      final rawTemplates = s['station_shift_templates'] as List? ?? [];

      final systems = rawSystems
          .map((sys) =>
              StationOperatingSystemModel.fromMap(sys as Map<String, dynamic>))
          .toList();

      final templates = rawTemplates
          .map((tmpl) =>
              StationShiftTemplate.fromMap(tmpl as Map<String, dynamic>))
          .toList();

      stations.add(StationModel.fromMap(
        s,
        operatingSystems: systems,
        shiftTemplates: templates,
      ));
    }
    return stations;
  }

  /// Add or Edit a station (available to all supervisors)
  Future<void> saveStation({
    String? stationId,
    required String orgId,
    required String supervisorId,
    required String name,
    required double latitude,
    required double longitude,
    required int punchRadius,
    required double fixedAmount,
    required List<String> tomSystems,
    required List<Map<String, String>> shiftTemplates,
  }) async {
    String targetStationId;

    if (stationId != null && stationId.isNotEmpty) {
      targetStationId = stationId;
      await _client.from('stations').update({
        'name': name.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'punch_radius_meters': punchRadius,
        'default_fixed_amount': fixedAmount,
      }).eq('id', targetStationId);

      await _client
          .from('station_operating_systems')
          .delete()
          .eq('station_id', targetStationId);
      await _client
          .from('station_shift_templates')
          .delete()
          .eq('station_id', targetStationId);
    } else {
      final res = await _client
          .from('stations')
          .insert({
            'org_id': orgId,
            'supervisor_id': supervisorId,
            'name': name.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'punch_radius_meters': punchRadius,
            'default_fixed_amount': fixedAmount,
          })
          .select()
          .single();
      targetStationId = res['id'] as String;
    }

    if (tomSystems.isNotEmpty) {
      final systemsPayload = tomSystems
          .map((sys) => {
                'station_id': targetStationId,
                'system_name': sys.trim(),
                'is_default': true,
              })
          .toList();
      await _client.from('station_operating_systems').insert(systemsPayload);
    }

    if (shiftTemplates.isNotEmpty) {
      final templatesPayload = shiftTemplates
          .map((tmpl) => {
                'station_id': targetStationId,
                'shift_name': tmpl['name']!,
                'start_time': tmpl['start']!,
                'end_time': tmpl['end']!,
              })
          .toList();
      await _client.from('station_shift_templates').insert(templatesPayload);
    }
  }

  Future<void> deleteStation(String stationId) async {
    await _client.from('stations').delete().eq('id', stationId);
  }
}
