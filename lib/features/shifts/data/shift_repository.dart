import 'package:supabase_flutter/supabase_flutter.dart';
import 'shift_model.dart';

class ShiftRepository {
  final SupabaseClient _client;

  ShiftRepository(this._client);

  Future<List<ShiftModel>> getSupervisorShifts(
    String orgId, {
    String? supervisorId,
    String? dutyDate,
  }) async {
    Future<List<ShiftModel>> load({required bool includePublisher}) async {
      final publisherField = includePublisher ? 'published_by_name,\n        ' : '';
      var query = _client.from('shifts').select('''
        id,
        org_id,
        station_id,
        duty_date,
        template_id,
        shift_name,
        start_time,
        end_time,
        daily_amount,
        is_published,
        ${publisherField}supervisor_id,
        stations (
          id,
          name
        ),
        shift_assignments (
          id,
          shift_id,
          operator_id,
          station_id,
          operating_system_id,
          is_ot,
          profiles (
            id,
            full_name
          ),
          station_operating_systems:operating_system_id (
            id,
            system_name
          )
        )
      ''');

      if (dutyDate != null && dutyDate.isNotEmpty) {
        query = query.eq('duty_date', dutyDate);
      }
      if (supervisorId != null && supervisorId.isNotEmpty) {
        query = query.eq('org_id', orgId).eq('supervisor_id', supervisorId);
      } else if (orgId.isNotEmpty) {
        query = query.eq('org_id', orgId);
      }

      final res = await query.order('duty_date', ascending: true);
      final rawList = res as List;
      return rawList.map<ShiftModel>((item) {
        final map = Map<String, dynamic>.from(item as Map);
        if (map['shift_assignments'] != null) {
          for (var sa in (map['shift_assignments'] as List)) {
            final sos = sa['station_operating_systems'];
            sa['system_name'] = sos is Map ? sos['system_name'] : 'TOM 01';
          }
        }
        final shiftId = map['id']?.toString() ?? '';
        final shiftStationId = map['station_id']?.toString() ?? '';
        if (map['shift_assignments'] is List) {
          final exactRows = (map['shift_assignments'] as List)
              .whereType<Map>()
              .where((sa) =>
                  sa['shift_id']?.toString() == shiftId &&
                  sa['station_id']?.toString() == shiftStationId)
              .toList();

          // Read-side guard for legacy duplicate rows: one TOM can be used by
          // many different shifts, so deduplicate ONLY by exact shift + TOM.
          final seenExactTom = <String>{};
          map['shift_assignments'] = exactRows.where((sa) {
            final tomId = sa['operating_system_id']?.toString() ?? '';
            final key = '$shiftId|$tomId';
            if (tomId.isEmpty || seenExactTom.add(key)) return true;
            return false;
          }).toList();
        }
        return ShiftModel.fromMap(map);
      }).toList();
    }

    try {
      return await load(includePublisher: true);
    } catch (_) {
      // Older databases may not have the optional publisher columns yet.
      // Never let that optional field hide the actual shift/operator roster.
      try {
        return await load(includePublisher: false);
      } catch (_) {
        return [];
      }
    }
  }

  /// Returns all published shifts for an organization.
  /// Used by the operator roster so every published supervisor shift is visible.
  Future<List<ShiftModel>> getPublishedShifts(
    String orgId, {
    required String supervisorId,
  }) async {
    try {
      if (orgId.isEmpty || supervisorId.isEmpty) return [];

      Future<List<ShiftModel>> load({required bool includePublisher}) async {
        final publisherField = includePublisher ? 'published_by_name,\n            ' : '';
        final res = await _client
            .from('shifts')
            .select('''
            id,
            org_id,
            station_id,
            duty_date,
            template_id,
            shift_name,
            start_time,
            end_time,
            daily_amount,
            is_published,
            ${publisherField}supervisor_id,
            stations (
              id,
              name,
              code,
              supervisor_id
            ),
            shift_assignments (
              id,
              shift_id,
              operator_id,
              station_id,
              operating_system_id,
              is_ot,
              profiles (
                id,
                full_name,
                role
              ),
              station_operating_systems:operating_system_id (
                id,
                system_name
              )
            )
          ''')
            .eq('org_id', orgId)
            .eq('supervisor_id', supervisorId)
            .eq('is_published', true)
            .order('duty_date', ascending: true);

        final rawList = res as List;
        return rawList.map<ShiftModel>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          if (map['shift_assignments'] != null) {
            for (var sa in (map['shift_assignments'] as List)) {
              final sos = sa['station_operating_systems'];
              sa['system_name'] = sos is Map ? sos['system_name'] : 'TOM 01';
            }
          }
          return ShiftModel.fromMap(map);
        }).toList();
      }

      try {
        return await load(includePublisher: true);
      } catch (_) {
        return await load(includePublisher: false);
      }
    } catch (_) {
      return [];
    }
  }

  Future<List<ShiftModel>> getOperatorShifts(String operatorId) async {
    if (operatorId.trim().isEmpty) return [];

    try {
      final res = await _client.rpc(
        'get_my_operator_roster',
        params: {'p_operator_id': operatorId},
      );
      final rows = (res as List?) ?? const [];
      final parsed = _parseOperatorRosterRows(rows, operatorId);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {
      // Fall back to direct assignment/shift queries for older databases.
    }

    try {
      final assignmentRes = await _client
          .from('shift_assignments')
          .select('id, shift_id, station_id, operating_system_id, operator_id, is_ot')
          .eq('operator_id', operatorId);

      final assignments = (assignmentRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (assignments.isEmpty) return [];

      final shiftIds = assignments
          .map((e) => e['shift_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (shiftIds.isEmpty) return [];

      List shiftRes;
      try {
        final res = await _client
            .from('shifts')
            .select('id, org_id, station_id, duty_date, template_id, shift_name, start_time, end_time, daily_amount, is_published, published_by_name, supervisor_id, stations (id, name, code)')
            .inFilter('id', shiftIds);
        shiftRes = res as List;
      } catch (_) {
        final res = await _client
            .from('shifts')
            .select('id, org_id, station_id, duty_date, template_id, shift_name, start_time, end_time, daily_amount, is_published, supervisor_id, stations (id, name, code)')
            .inFilter('id', shiftIds);
        shiftRes = res as List;
      }

      final rows = shiftRes
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isEmpty) return [];

      final shiftsById = <String, Map<String, dynamic>>{
        for (final row in rows) row['id'].toString(): row,
      };
      final byShift = <String, ShiftModel>{};

      for (final a in assignments) {
        final shiftId = a['shift_id']?.toString() ?? '';
        final shift = shiftsById[shiftId];
        if (shift == null || shift['is_published'] != true) continue;

        try {
          final assignment = ShiftAssignmentModel(
            id: a['id']?.toString() ?? '',
            shiftId: shiftId,
            stationId: a['station_id']?.toString() ?? shift['station_id']?.toString() ?? '',
            operatingSystemId: a['operating_system_id']?.toString() ?? '',
            systemName: 'TOM 01',
            operatorId: operatorId,
            operatorName: '',
            isOt: a['is_ot'] == true,
          );
          final station = shift['stations'] is Map
              ? Map<String, dynamic>.from(shift['stations'] as Map)
              : <String, dynamic>{};
          byShift[shiftId] = ShiftModel.fromMap({
            ...shift,
            'station_name': station['name'] ?? 'Station',
          }, assignments: [assignment]);
        } catch (_) {
          // Ignore malformed rows and keep the remaining roster.
        }
      }

      final result = byShift.values.toList();
      result.sort((a, b) {
        final d = a.dutyDate.compareTo(b.dutyDate);
        if (d != 0) return d;
        final t = a.startTime.compareTo(b.startTime);
        return t != 0 ? t : a.shiftName.compareTo(b.shiftName);
      });
      return result;
    } catch (_) {
      return [];
    }
  }

  List<ShiftModel> _parseOperatorRosterRows(List rows, String operatorId) {
    final byShift = <String, ShiftModel>{};
    for (final raw in rows) {
      final m = Map<String, dynamic>.from(raw as Map);
      final shiftId = m['shift_id']?.toString() ?? '';
      if (shiftId.isEmpty) continue;
      final assignment = ShiftAssignmentModel(
        id: m['assignment_id']?.toString() ?? '',
        shiftId: shiftId,
        stationId: m['station_id']?.toString() ?? '',
        operatingSystemId: m['operating_system_id']?.toString() ?? '',
        systemName: m['system_name']?.toString() ?? 'TOM 01',
        operatorId: m['operator_id']?.toString() ?? operatorId,
        operatorName: m['operator_name']?.toString() ?? '',
        isOt: m['is_ot'] == true,
      );
      byShift[shiftId] = ShiftModel.fromMap({
        'id': shiftId,
        'org_id': m['org_id'],
        'station_id': m['station_id'],
        'station_name': m['station_name'] ?? 'Station',
        'shift_name': m['shift_name'],
        'duty_date': m['duty_date'],
        'start_time': m['start_time'],
        'end_time': m['end_time'],
        'daily_amount': m['daily_amount'],
        'is_published': m['is_published'] == true,
        'published_by_name': m['published_by_name'],
      }, assignments: [assignment]);
    }
    final result = byShift.values.toList();
    result.sort((a, b) {
      final d = a.dutyDate.compareTo(b.dutyDate);
      if (d != 0) return d;
      final t = a.startTime.compareTo(b.startTime);
      return t != 0 ? t : a.shiftName.compareTo(b.shiftName);
    });
    return result;
  }

  Future<void> createAndPublishShift({
    required String orgId,
    required String supervisorId,
    required String stationId,
    required String shiftName,
    required String dutyDate,
    String? templateId,
    required String startTime,
    required String endTime,
    required double dailyAmount,
    required List<Map<String, dynamic>> rawAssignments,
    String? existingShiftId,
    List<String> clearedOperatingSystemIds = const [],
    required String publisherId,
    required String publisherName,
    List<String> removedOperatingSystemIds = const [],
  }) async {
    try {
      // 1. Insert or update the shift row
      Map<String, dynamic>? existingShift;
      if (existingShiftId != null && existingShiftId.trim().isNotEmpty) {
        existingShift = await _client
            .from('shifts')
            .select('id')
            .eq('id', existingShiftId)
            .eq('station_id', stationId)
            .eq('supervisor_id', supervisorId)
            .eq('org_id', orgId)
            .maybeSingle();
      } else if (templateId != null && templateId.trim().isNotEmpty) {
        existingShift = await _client
            .from('shifts')
            .select('id')
            .eq('station_id', stationId)
            .eq('duty_date', dutyDate)
            .eq('template_id', templateId)
            .eq('supervisor_id', supervisorId)
            .eq('org_id', orgId)
            .maybeSingle();
      } else {
        existingShift = await _client
            .from('shifts')
            .select('id')
            .eq('station_id', stationId)
            .eq('duty_date', dutyDate)
            .eq('shift_name', shiftName)
            .eq('start_time', startTime)
            .eq('end_time', endTime)
            .eq('supervisor_id', supervisorId)
            .eq('org_id', orgId)
            .maybeSingle();
      }

      String shiftId;
      if (existingShift != null) {
        shiftId = existingShift['id'] as String;
        await _client
            .from('shifts')
            .update({
              'supervisor_id': supervisorId,
              if (templateId != null && templateId.trim().isNotEmpty) 'template_id': templateId,
              'start_time': startTime,
              'end_time': endTime,
              'daily_amount': dailyAmount,
              'is_published': true,
              'published_at': DateTime.now().toIso8601String(),
              'published_by': publisherId,
              'published_by_name': publisherName,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', shiftId);
      } else {
        try {
          final inserted = await _client
              .from('shifts')
              .insert({
                if (orgId.isNotEmpty) 'org_id': orgId,
                'supervisor_id': supervisorId,
                if (templateId != null && templateId.trim().isNotEmpty) 'template_id': templateId,
                'station_id': stationId,
                'shift_name': shiftName,
                'duty_date': dutyDate,
                'start_time': startTime,
                'end_time': endTime,
                'daily_amount': dailyAmount,
                'is_published': true,
                'published_at': DateTime.now().toIso8601String(),
                'published_by': publisherId,
                'published_by_name': publisherName,
              })
              .select('id')
              .single();
          shiftId = inserted['id'] as String;
        } on PostgrestException catch (e) {
          // A concurrent publish can win the natural shift key between the
          // lookup above and this insert. Treat that duplicate as idempotent
          // and continue with the already-created shift.
          if (e.code != '23505' && e.code != '409') rethrow;
          final concurrentShift = await _client
              .from('shifts')
              .select('id')
              .eq('station_id', stationId)
              .eq('duty_date', dutyDate)
              .eq('shift_name', shiftName)
              .eq('start_time', startTime)
              .eq('end_time', endTime)
              .eq('supervisor_id', supervisorId)
              .eq('org_id', orgId)
              .maybeSingle();
          if (concurrentShift == null) rethrow;
          shiftId = concurrentShift['id'] as String;
        }
      }

      // 2. Keep the existing station-system safety behavior. The station
      // systems are checked once per shift before assignment writes.
      final existingSystemsRes = await _client
          .from('station_operating_systems')
          .select('id')
          .eq('station_id', stationId);
      final validSystemIds = (existingSystemsRes as List)
          .map((e) => e['id'].toString())
          .toList();

      // Preserve the existing fallback for stations with fewer system rows.
      if (rawAssignments.isNotEmpty &&
          validSystemIds.length < rawAssignments.length) {
        final neededCount = rawAssignments.length - validSystemIds.length;
        final newSystems = List.generate(
          neededCount,
          (i) => {
            'station_id': stationId,
            'system_name': 'TOM 0${validSystemIds.length + i + 1}',
            'is_active': true,
          },
        );
        await _client
            .from('station_operating_systems')
            .insert(newSystems)
            .select('id');
      }

      // 3. Change assignments ONLY inside this exact shift.
      // Never replace/cascade assignment rows across other shifts.
      final removedSystems = removedOperatingSystemIds.toSet();
      final clearedSystems = clearedOperatingSystemIds.toSet();

      // Explicit TOM deletion/unassignment is scoped by both shift_id and
      // operating_system_id. A TOM with the same ID in another shift is
      // completely untouched. Delete all requested counters in one query.
      final systemsToClear = {...removedSystems, ...clearedSystems}
          .where((id) => id.isNotEmpty)
          .toList();
      if (systemsToClear.isNotEmpty) {
        await _client
            .from('shift_assignments')
            .delete()
            .eq('shift_id', shiftId)
            .inFilter('operating_system_id', systemsToClear);
      }

      // Load the existing rows for this exact shift once. This avoids one
      // SELECT per TOM and still keeps all writes isolated to shift_id.
      final existingRows = await _client
          .from('shift_assignments')
          .select('id, operating_system_id')
          .eq('shift_id', shiftId)
          .order('id');
      final existingBySystem = <String, List<String>>{};
      for (final raw in existingRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final sysId = row['operating_system_id']?.toString() ?? '';
        final rowId = row['id']?.toString() ?? '';
        if (sysId.isEmpty || rowId.isEmpty) continue;
        existingBySystem.putIfAbsent(sysId, () => []).add(rowId);
      }

      // Update existing rows in parallel and batch all new rows into one
      // insert. Legacy duplicates are removed only for this exact shift/TOM.
      final newAssignmentRows = <Map<String, dynamic>>[];
      final writes = <Future<void>>[];
      for (final a in rawAssignments) {
        final sysId = a['operating_system_id']?.toString() ?? '';
        final opId = a['operator_id']?.toString() ?? '';
        if (sysId.isEmpty ||
            opId.isEmpty ||
            removedSystems.contains(sysId) ||
            clearedSystems.contains(sysId)) {
          continue;
        }

        final values = <String, dynamic>{
          if (orgId.isNotEmpty) 'org_id': orgId,
          'shift_id': shiftId,
          'station_id': stationId,
          'operating_system_id': sysId,
          'operator_id': opId,
          'is_ot': a['is_ot'] == true,
        };
        final rowIds = existingBySystem[sysId] ?? const <String>[];
        if (rowIds.isEmpty) {
          newAssignmentRows.add(values);
          continue;
        }

        final keepId = rowIds.first;
        writes.add(
          _client
              .from('shift_assignments')
              .update({
                'station_id': stationId,
                'operator_id': opId,
                'is_ot': a['is_ot'] == true,
              })
              .eq('id', keepId)
              .eq('shift_id', shiftId)
              .eq('operating_system_id', sysId),
        );
        for (final duplicateId in rowIds.skip(1)) {
          writes.add(
            _client
                .from('shift_assignments')
                .delete()
                .eq('id', duplicateId)
                .eq('shift_id', shiftId)
                .eq('operating_system_id', sysId),
          );
        }
      }

      if (writes.isNotEmpty) await Future.wait(writes);
      if (newAssignmentRows.isNotEmpty) {
        await _client.from('shift_assignments').insert(newAssignmentRows);
      }

      // Attendance is generated only when a duty is actually completed.
      // Do not reconcile here: doing so used to mark future published duties
      // PRESENT immediately and also added one network round-trip per shift.
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteShift(String shiftId) async {
    await _client.from('shift_assignments').delete().eq('shift_id', shiftId);
    await _client.from('shifts').delete().eq('id', shiftId);

    // No attendance reconciliation on delete. Future duties must disappear
    // from the operator roster immediately and must never become PRESENT.
  }
}
