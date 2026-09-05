import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shift_assignment_model.dart';
import 'shift_model.dart';

class ShiftRepository {
  final SupabaseClient _client;

  ShiftRepository(this._client);

  Future<List<ShiftModel>> getSupervisorShifts(
    String orgId, {
    required String supervisorId,
    String? dutyDate,
  }) async {
    try {
      var query = _client.from('shifts').select('''
        id,
        org_id,
        station_id,
        supervisor_id,
        shift_name,
        duty_date,
        start_time,
        end_time,
        daily_amount,
        is_published,
        published_at,
        created_at,
        updated_at,
        stations:station_id (
          id,
          name
        ),
        shift_assignments (
          id,
          shift_id,
          station_id,
          operating_system_id,
          operator_id,
          is_ot,
          profiles:operator_id (
            id,
            full_name,
            phone_number,
            emp_code
          ),
          station_operating_systems:operating_system_id (
            id,
            system_name
          )
        )
      ''');

      if (supervisorId.isNotEmpty) {
        query = query.eq('supervisor_id', supervisorId);
      }

      if (dutyDate != null && dutyDate.isNotEmpty) {
        query = query.eq('duty_date', dutyDate);
      }

      final shiftsRes = await query.order('duty_date', ascending: false);
      final List<ShiftModel> result = [];

      for (final s in (shiftsRes as List)) {
        final shiftId = s['id']?.toString() ?? '';
        final stationMap = s['stations'] as Map<String, dynamic>?;
        final stationName = stationMap?['name']?.toString() ?? 'Station';

        final rawAssignments = (s['shift_assignments'] as List?) ?? [];
        final List<ShiftAssignmentModel> assignments = [];

        for (final a in rawAssignments) {
          final profileMap = a['profiles'] as Map<String, dynamic>?;
          final osMap = a['station_operating_systems'] as Map<String, dynamic>?;

          assignments.add(
            ShiftAssignmentModel(
              id: a['id']?.toString() ?? '',
              shiftId: shiftId,
              stationId: s['station_id']?.toString() ?? '',
              operatingSystemId: a['operating_system_id']?.toString() ?? '',
              systemName: osMap?['system_name']?.toString() ?? 'TOM Counter',
              operatorId: a['operator_id']?.toString() ?? '',
              operatorName: profileMap?['full_name']?.toString() ?? 'Operator',
              isOt: a['is_ot'] as bool? ?? false,
            ),
          );
        }

        final shiftMap = Map<String, dynamic>.from(s);
        shiftMap['station_name'] = stationName;

        result.add(ShiftModel.fromMap(shiftMap, assignments: assignments));
      }

      return result;
    } catch (e, st) {
      debugPrint('❌ [GET SHIFTS ERROR]: $e\n$st');
      return [];
    }
  }

  Future<List<ShiftModel>> getOperatorShifts(String operatorId) async {
    try {
      final res = await _client
          .from('shift_assignments')
          .select('''
            id,
            shift_id,
            operating_system_id,
            is_ot,
            shifts:shift_id (
              id,
              org_id,
              station_id,
              supervisor_id,
              shift_name,
              duty_date,
              start_time,
              end_time,
              daily_amount,
              is_published,
              stations:station_id (
                id,
                name
              )
            ),
            station_operating_systems:operating_system_id (
              id,
              system_name
            )
          ''')
          .eq('operator_id', operatorId);

      final List<ShiftModel> operatorShifts = [];

      for (final a in (res as List)) {
        final shiftData = a['shifts'] as Map<String, dynamic>?;
        if (shiftData == null) continue;

        final stationMap = shiftData['stations'] as Map<String, dynamic>?;
        final osMap = a['station_operating_systems'] as Map<String, dynamic>?;

        final assignment = ShiftAssignmentModel(
          id: a['id']?.toString() ?? '',
          shiftId: shiftData['id']?.toString() ?? '',
          stationId: shiftData['station_id']?.toString() ?? '',
          operatingSystemId: a['operating_system_id']?.toString() ?? '',
          systemName: osMap?['system_name']?.toString() ?? 'TOM Counter',
          operatorId: operatorId,
          operatorName: '',
          isOt: a['is_ot'] as bool? ?? false,
        );

        final shiftMap = Map<String, dynamic>.from(shiftData);
        shiftMap['station_name'] = stationMap?['name']?.toString() ?? 'Station';

        operatorShifts.add(
          ShiftModel.fromMap(shiftMap, assignments: [assignment]),
        );
      }

      return operatorShifts;
    } catch (e, st) {
      debugPrint('❌ [OPERATOR SHIFTS ERROR]: $e\n$st');
      return [];
    }
  }

  Future<void> createAndPublishShift({
    required String orgId,
    required String supervisorId,
    required String stationId,
    required String shiftName,
    required String dutyDate,
    required String startTime,
    required String endTime,
    required double dailyAmount,
    required List<Map<String, dynamic>> rawAssignments,
  }) async {
    try {
      // 1. Insert or update the shift row
      final existingShift = await _client
          .from('shifts')
          .select('id')
          .eq('station_id', stationId)
          .eq('duty_date', dutyDate)
          .eq('shift_name', shiftName)
          .maybeSingle();

      String shiftId;
      if (existingShift != null) {
        shiftId = existingShift['id'] as String;
        await _client
            .from('shifts')
            .update({
              'supervisor_id': supervisorId,
              'start_time': startTime,
              'end_time': endTime,
              'daily_amount': dailyAmount,
              'is_published': true,
              'published_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', shiftId);
      } else {
        final inserted = await _client
            .from('shifts')
            .insert({
              if (orgId.isNotEmpty) 'org_id': orgId,
              'supervisor_id': supervisorId,
              'station_id': stationId,
              'shift_name': shiftName,
              'duty_date': dutyDate,
              'start_time': startTime,
              'end_time': endTime,
              'daily_amount': dailyAmount,
              'is_published': true,
              'published_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();
        shiftId = inserted['id'] as String;
      }

      // 2. Fetch all real operating system IDs present in DB for this station
      final existingSystemsRes = await _client
          .from('station_operating_systems')
          .select('id')
          .eq('station_id', stationId);

      List<String> validSystemIds = (existingSystemsRes as List)
          .map((e) => e['id'].toString())
          .toList();

      // Ensure at least 3 distinct systems exist in DB so multiple counters never clash
      if (validSystemIds.length < rawAssignments.length) {
        final neededCount = rawAssignments.length - validSystemIds.length;
        final newSystems = List.generate(
          neededCount,
          (i) => {
            'station_id': stationId,
            'system_name': 'TOM 0${validSystemIds.length + i + 1}',
            'is_active': true,
          },
        );

        final created = await _client
            .from('station_operating_systems')
            .insert(newSystems)
            .select('id');

        for (final row in created as List) {
          validSystemIds.add(row['id'].toString());
        }
      }

      // 3. Clear previous assignments for this shift
      await _client.from('shift_assignments').delete().eq('shift_id', shiftId);

      // 4. Insert assignments guaranteeing DISTINCT operating_system_id per shift
      if (rawAssignments.isNotEmpty) {
        final Set<String> usedSystemIds = {};
        final List<Map<String, dynamic>> assignmentsToInsert = [];

        for (int i = 0; i < rawAssignments.length; i++) {
          final a = rawAssignments[i];
          final requestedSysId = a['operating_system_id']?.toString() ?? '';

          String safeSysId;
          if (validSystemIds.contains(requestedSysId) &&
              !usedSystemIds.contains(requestedSysId)) {
            safeSysId = requestedSysId;
          } else {
            // Pick an unused operating system ID
            safeSysId = validSystemIds.firstWhere(
              (id) => !usedSystemIds.contains(id),
              orElse: () => validSystemIds[i % validSystemIds.length],
            );
          }

          usedSystemIds.add(safeSysId);

          assignmentsToInsert.add({
            if (orgId.isNotEmpty) 'org_id': orgId,
            'shift_id': shiftId,
            'station_id': stationId,
            'operating_system_id': safeSysId,
            'operator_id': a['operator_id'],
            'is_ot': a['is_ot'] ?? false,
          });
        }

        await _client.from('shift_assignments').insert(assignmentsToInsert);
      }
    } catch (e, st) {
      debugPrint('❌ [PUBLISH SHIFT FAILED]: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteShift(String shiftId) async {
    await _client.from('shift_assignments').delete().eq('shift_id', shiftId);
    await _client.from('shifts').delete().eq('id', shiftId);
  }
}
