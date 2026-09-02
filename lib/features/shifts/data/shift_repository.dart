import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shift_model.dart';

class ShiftRepository {
  final SupabaseClient _client;

  ShiftRepository(this._client);

  Future<List<ShiftModel>> getSupervisorShifts(String orgId) async {
    try {
      final shiftsRes = await _client
          .from('shifts')
          .select('*, stations(name)')
          .eq('org_id', orgId)
          .order('duty_date', ascending: false);

      final List<ShiftModel> result = [];

      for (final s in (shiftsRes as List)) {
        final shiftId = s['id'];

        final assignmentsData = await _client
            .from('shift_assignments')
            .select()
            .eq('shift_id', shiftId);

        final List<ShiftAssignmentModel> assignments = [];

        for (final a in (assignmentsData as List)) {
          String operatorName = 'Soldier';
          final opId = a['operator_id'];
          if (opId != null) {
            final pRes = await _client
                .from('profiles')
                .select('full_name')
                .eq('id', opId)
                .maybeSingle();
            if (pRes != null && pRes['full_name'] != null) {
              operatorName = pRes['full_name'];
            }
          }

          String systemName = 'TOM Counter';
          final osId = a['operating_system_id'];
          if (osId != null) {
            final osRes = await _client
                .from('station_operating_systems')
                .select('system_name')
                .eq('id', osId)
                .maybeSingle();
            if (osRes != null && osRes['system_name'] != null) {
              systemName = osRes['system_name'];
            }
          }

          assignments.add(
            ShiftAssignmentModel(
              id: a['id']?.toString() ?? '',
              shiftId: shiftId,
              stationId: s['station_id']?.toString() ?? '',
              operatingSystemId: osId?.toString() ?? '',
              systemName: systemName,
              operatorId: opId?.toString() ?? '',
              operatorName: operatorName,
              isOt: a['is_ot'] as bool? ?? false,
            ),
          );
        }

        result.add(ShiftModel.fromMap(s, assignments: assignments));
      }

      return result;
    } catch (e, st) {
      debugPrint('❌ [GET SHIFTS ERROR]: $e\n$st');
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
      // 1. Find if shift already exists for this station + date + name
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
              'start_time': startTime,
              'end_time': endTime,
              'daily_amount': dailyAmount,
              'is_published': true,
              'published_at': DateTime.now().toIso8601String(),
            })
            .eq('id', shiftId);
      } else {
        final inserted = await _client
            .from('shifts')
            .insert({
              'org_id': orgId,
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

      debugPrint('📍 [SHIFT RECORD ID]: $shiftId');

      // 2. Delete existing assignments for this shift
      await _client.from('shift_assignments').delete().eq('shift_id', shiftId);

      // 3. Insert fresh assignments
      final assignmentsToInsert = rawAssignments.map((a) {
        return {
          'org_id': orgId,
          'shift_id': shiftId,
          'station_id': stationId,
          'operating_system_id': a['operating_system_id'],
          'operator_id': a['operator_id'],
          'is_ot': a['is_ot'] ?? false,
        };
      }).toList();

      final insertedList = await _client
          .from('shift_assignments')
          .insert(assignmentsToInsert)
          .select();

      debugPrint(
        '✅ [DATABASE INSERT SUCCESS] Row count: ${insertedList.length}',
      );
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
