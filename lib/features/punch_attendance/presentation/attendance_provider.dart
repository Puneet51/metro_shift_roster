import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/punch_attendance/data/attendance_model.dart';
import 'package:metro_shift_roster/features/punch_attendance/data/attendance_repository.dart';

// 1. Attendance Repository Provider
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(SupabaseService.client);
});

// 2. Active Punch Session (Map return type for compatibility across all screens)
final activePunchSessionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null || user.role != 'operator') {
        return null;
      }


      try {
        // The database blocks a new punch when an open session exists.
        // Therefore the UI must use punch_out_at IS NULL as the authoritative
        // open-session check, rather than relying only on one status value.
        final openRows = await SupabaseService.client
            .from('punch_sessions')
            .select('id, operator_id, station_id, shift_id, duty_date, punch_in_at, punch_out_at, status, stations(*)')
            .eq('operator_id', user.id)
            .filter('punch_out_at', 'is', 'null')
            .order('punch_in_at', ascending: false)
            .limit(5);

        for (final row in openRows as List) {
        }

        if (openRows.isNotEmpty) {
          final response = Map<String, dynamic>.from(openRows.first as Map);
          response['punch_in_time'] = response['punch_in_at'];
          return response;
        }


        final attRows = await SupabaseService.client
            .from('attendance')
            .select('id, operator_id, station_id, shift_id, duty_date, status, punch_in_time, punch_out_time, stations(*)')
            .eq('operator_id', user.id)
            .not('punch_in_time', 'is', null)
            .filter('punch_out_time', 'is', 'null')
            .order('punch_in_time', ascending: false)
            .limit(5);

        for (final row in attRows as List) {
        }

        if (attRows.isNotEmpty) {
          final response = Map<String, dynamic>.from(attRows.first as Map);
          return response;
        }

        return null;
      } catch (e, st) {
        rethrow;
      }
    });

// 3. Daily Duty Completion Check (Enforces strictly once-per-day punch cycle)
final hasCompletedPunchTodayProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || user.role != 'operator') return false;

  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.hasCompletedPunchToday(user.id);
});

// 4. Punch Audit History (Map return type for compatibility with punch_audit_check_screen)
final punchAuditListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null || user.role != 'operator') return [];

      final response = await SupabaseService.client
          .from('punch_sessions')
          .select('*, stations(*)')
          .eq('operator_id', user.id)
          .order('punch_in_at', ascending: false)
          .limit(50);

      final list = List<Map<String, dynamic>>.from(response as List);
      for (final item in list) {
        item['punch_in_time'] = item['punch_in_at'];
        item['punch_out_time'] = item['punch_out_at'];
      }
      return list;
    });

// 5. Operator Summary Metrics Provider
final operatorSummaryMetricsProvider =
    FutureProvider.autoDispose<AttendanceSummaryModel>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null || user.role != 'operator') {
        return const AttendanceSummaryModel(
          totalDuty: 0,
          earnings: 0.0,
          otDutyCount: 0,
          weekOffCount: 0,
        );
      }

      final repo = ref.watch(attendanceRepositoryProvider);
      return repo.getOperatorSummaryMetrics(user.id);
    });

// 6. Attendance StateNotifier
class AttendanceNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  AttendanceNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<void> punchIn({
    required String stationId,
    required double latitude,
    required double longitude,
    required List<double> faceEmbedding,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(attendanceRepositoryProvider);
      final res = await repo.punchIn(
        stationId: stationId,
        lat: latitude,
        lng: longitude,
        faceEmbedding: faceEmbedding,
      );

      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'Punch in failed');
      }

      _invalidateAttendanceData();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> punchOut({
    required String sessionId,
    required double latitude,
    required double longitude,
    required List<double> faceEmbedding,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(attendanceRepositoryProvider);
      final res = await repo.punchOut(
        sessionId: sessionId,
        lat: latitude,
        lng: longitude,
        faceEmbedding: faceEmbedding,
      );

      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'Punch out failed');
      }

      _invalidateAttendanceData();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _invalidateAttendanceData() {
    _ref.invalidate(activePunchSessionProvider);
    _ref.invalidate(hasCompletedPunchTodayProvider);
    _ref.invalidate(punchAuditListProvider);
    _ref.invalidate(operatorSummaryMetricsProvider);
  }
}

final attendanceNotifierProvider =
    StateNotifierProvider<AttendanceNotifier, AsyncValue<void>>((ref) {
      return AttendanceNotifier(ref);
    });
