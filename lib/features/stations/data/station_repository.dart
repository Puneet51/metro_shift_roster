import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'station_model.dart';

class StationRepository {
  final SupabaseClient _client;

  StationRepository(this._client);

  /// Dynamically fetches stations for operators, supervisors, and admins
  Future<List<StationModel>> getStations(
    String orgId, {
    String? supervisorId,
    bool isAdmin = false,
    bool isOperator = false,
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

      // If user is a supervisor (not admin, not operator), filter to their stations
      if (!isAdmin && !isOperator) {
        if (supervisorId == null || supervisorId.isEmpty || orgId.isEmpty) {
          return [];
        }

        // Primary supervisors and relievers use the same effective
        // supervisor scope. Never broaden this query to the whole org.
        query = query.eq('org_id', orgId).eq('supervisor_id', supervisorId);
      } else if (isOperator) {
        // Operators see only stations owned by their effective supervisor.
        if (supervisorId == null || supervisorId.isEmpty || orgId.isEmpty) {
          return [];
        }
        query = query.eq('org_id', orgId).eq('supervisor_id', supervisorId);
      } else if (orgId.isNotEmpty) {
        // Admins may see active stations in their organization.
        query = query.eq('org_id', orgId);
      } else {
        return [];
      }

      final res = await query.order('name', ascending: true);
      final list = (res as List)
          .map<StationModel>(
            (map) =>
                StationModel.fromMap(Map<String, dynamic>.from(map as Map)),
          )
          .toList();

      return list;
    } catch (e) {
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
        'default_fixed_amount': fixedAmount,
        'shift_templates': shiftTemplates,
        'is_active': true,
      };

      if (isNew) {
        await _client.from('stations').insert(data);
      } else {
        var updateQuery = _client
            .from('stations')
            .update(data)
            .eq('id', targetId)
            .eq('org_id', orgId)
            .eq('supervisor_id', supervisorId);

        await updateQuery;
      }

      // Preserve existing operating-system IDs. Deleting/recreating these
      // rows used to cascade/remove shift assignments whenever a station was
      // edited (for example, when adding a new shift template). Existing
      // duties must remain assigned until the supervisor manually changes
      // them.
      final existingSystemsRes = await _client
          .from('station_operating_systems')
          .select('id, system_name, is_active')
          .eq('station_id', targetId);
      final existingSystems = (existingSystemsRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final byName = <String, Map<String, dynamic>>{
        for (final row in existingSystems)
          (row['system_name']?.toString().trim().toLowerCase() ?? ''): row,
      };
      final desiredNames = tomSystems
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final desiredKeys = desiredNames.map((s) => s.toLowerCase()).toSet();

      await Future.wait(desiredNames.map((name) async {
        final key = name.toLowerCase();
        final existing = byName[key];
        if (existing != null) {
          await _client
              .from('station_operating_systems')
              .update({'system_name': name, 'is_active': true})
              .eq('id', existing['id']);
        } else {
          await _client.from('station_operating_systems').insert({
            'id': const Uuid().v4(),
            'station_id': targetId,
            'system_name': name,
            'is_active': true,
          });
        }
      }));

      // Do not delete a system that is referenced by an existing shift
      // assignment. Keep it inactive instead so historical/current duties
      // retain their operator assignment.
      await Future.wait(existingSystems.map((row) async {
        final name = row['system_name']?.toString().trim().toLowerCase() ?? '';
        if (name.isEmpty || desiredKeys.contains(name)) return;
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) return;
        final refs = await _client
            .from('shift_assignments')
            .select('id')
            .eq('operating_system_id', id)
            .limit(1);
        if ((refs as List).isNotEmpty) {
          await _client
              .from('station_operating_systems')
              .update({'is_active': false})
              .eq('id', id);
        } else {
          await _client
              .from('station_operating_systems')
              .delete()
              .eq('id', id);
        }
      }));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteStation({
    required String stationId,
    required String orgId,
    required String supervisorId,
  }) async {
    if (orgId.isEmpty || supervisorId.isEmpty) {
      throw Exception('No supervisor scope available');
    }

    // Only delete child systems after confirming the station belongs to
    // this supervisor and organization.
    final station = await _client
        .from('stations')
        .select('id')
        .eq('id', stationId)
        .eq('org_id', orgId)
        .eq('supervisor_id', supervisorId)
        .maybeSingle();

    if (station == null) {
      throw Exception('Station not found in your supervisor scope');
    }

    await _client
        .from('station_operating_systems')
        .delete()
        .eq('station_id', stationId);

    await _client
        .from('stations')
        .delete()
        .eq('id', stationId)
        .eq('org_id', orgId)
        .eq('supervisor_id', supervisorId);
  }
}
