import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'station_model.dart';

class StationRepository {
  final SupabaseClient _client;

  StationRepository(this._client);

  /// Dynamically fetches stations strictly matching the requesting supervisor
  Future<List<StationModel>> getStations(
    String orgId, {
    required String supervisorId,
    required bool isAdmin,
  }) async {
    try {
      var query = _client
          .from('stations')
          .select('''
        id,
        org_id,
        supervisor_id,
        name,
        code,
        latitude,
        longitude,
        punch_radius_meters,
        default_fixed_amount,
        shift_templates,
        is_active,
        created_at,
        station_operating_systems (
          id,
          station_id,
          system_name,
          is_active
        )
      ''')
          .eq('is_active', true);

      // Strict dynamic check: Non-admins only see stations matching their own supervisor ID
      if (!isAdmin) {
        if (supervisorId.isEmpty) return [];
        query = query.eq('supervisor_id', supervisorId);
      }

      final res = await query.order('name', ascending: true);

      return (res as List)
          .map<StationModel>(
            (map) =>
                StationModel.fromMap(Map<String, dynamic>.from(map as Map)),
          )
          .toList();
    } catch (e, st) {
      debugPrint('❌ [GET STATIONS ERROR]: $e\n$st');
      return [];
    }
  }

  /// Dynamically creates or updates station along with operating systems
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
    try {
      final isNew = stationId == null || stationId.isEmpty;
      final targetId = isNew ? const Uuid().v4() : stationId;
      final cleanCode = name.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final code = cleanCode.length >= 4
          ? cleanCode.substring(0, 4)
          : cleanCode;

      final data = {
        'id': targetId,
        if (orgId.isNotEmpty) 'org_id': orgId,
        'supervisor_id': supervisorId,
        'name': name.trim(),
        'code': code,
        'latitude': latitude,
        'longitude': longitude,
        'punch_radius_meters': punchRadius,
        'default_fixed_amount': fixedAmount,
        'shift_templates': shiftTemplates,
        'is_active': true,
      };

      if (isNew) {
        await _client.from('stations').insert(data);
      } else {
        await _client.from('stations').update(data).eq('id', targetId);
      }

      await _client
          .from('station_operating_systems')
          .delete()
          .eq('station_id', targetId);

      if (tomSystems.isNotEmpty) {
        final systemsToInsert = tomSystems
            .map(
              (sys) => {
                'id': const Uuid().v4(),
                'station_id': targetId,
                'system_name': sys.trim(),
                'is_active': true,
              },
            )
            .toList();

        await _client.from('station_operating_systems').insert(systemsToInsert);
      }
    } catch (e, st) {
      debugPrint('❌ [SAVE STATION ERROR]: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteStation(String stationId) async {
    await _client
        .from('station_operating_systems')
        .delete()
        .eq('station_id', stationId);
    await _client.from('stations').delete().eq('id', stationId);
  }
}
