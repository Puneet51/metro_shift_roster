import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// Model for Shift Assignment with full Operator and Shift details
class EnrichedShiftAssignment {
  final String id;
  final String shiftId;
  final String operatorId;
  final String operatorName;
  final String shiftName;
  final String stationName;
  final String startTime;
  final String endTime;
  final String dutyDate;
  final bool isOt;

  EnrichedShiftAssignment({
    required this.id,
    required this.shiftId,
    required this.operatorId,
    required this.operatorName,
    required this.shiftName,
    required this.stationName,
    required this.startTime,
    required this.endTime,
    required this.dutyDate,
    required this.isOt,
  });

  factory EnrichedShiftAssignment.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final shift = map['shifts'] as Map<String, dynamic>?;
    final station = shift?['stations'] as Map<String, dynamic>?;

    return EnrichedShiftAssignment(
      id: map['id'] ?? '',
      shiftId: map['shift_id'] ?? '',
      operatorId: map['operator_id'] ?? '',
      operatorName: profile?['full_name'] ?? 'Unassigned Operator',
      shiftName: shift?['shift_name'] ?? 'General Shift',
      stationName: station?['name'] ?? 'Metro Station',
      startTime: shift?['start_time'] ?? '--:--',
      endTime: shift?['end_time'] ?? '--:--',
      dutyDate: shift?['duty_date'] ?? '',
      isOt: map['is_ot'] ?? false,
    );
  }
}

// 1. Supervisor Realtime Provider: Streams ALL duty assignments for a given date
final supervisorLiveRosterProvider = StreamProvider.autoDispose
    .family<List<EnrichedShiftAssignment>, String>((ref, date) {
      // Listen to live stream from shift_assignments
      return supabase
          .from('shift_assignments')
          .stream(primaryKey: ['id'])
          .asyncMap((_) async {
            // Fetch full join with profiles, shifts, and stations
            final response = await supabase
                .from('shift_assignments')
                .select('''
              id,
              shift_id,
              operator_id,
              is_ot,
              created_at,
              profiles:operator_id (
                id,
                full_name,
                role
              ),
              shifts:shift_id (
                id,
                shift_name,
                start_time,
                end_time,
                duty_date,
                stations:station_id (
                  id,
                  name
                )
              )
            ''')
                .order('created_at', ascending: false);

            return (response as List)
                .map((row) => EnrichedShiftAssignment.fromMap(row))
                .toList();
          });
    });

// 2. Operator Realtime Provider: Streams assignments for the logged-in Operator
final operatorLiveRosterProvider =
    StreamProvider.autoDispose<List<EnrichedShiftAssignment>>((ref) {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return const Stream.empty();

      return supabase
          .from('shift_assignments')
          .stream(primaryKey: ['id'])
          .eq('operator_id', currentUserId)
          .asyncMap((_) async {
            final response = await supabase
                .from('shift_assignments')
                .select('''
              id,
              shift_id,
              operator_id,
              is_ot,
              created_at,
              profiles:operator_id (
                id,
                full_name,
                role
              ),
              shifts:shift_id (
                id,
                shift_name,
                start_time,
                end_time,
                duty_date,
                stations:station_id (
                  id,
                  name
                )
              )
            ''')
                .eq('operator_id', currentUserId)
                .order('created_at', ascending: false);

            return (response as List)
                .map((row) => EnrichedShiftAssignment.fromMap(row))
                .toList();
          });
    });
