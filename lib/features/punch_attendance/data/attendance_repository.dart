import 'package:supabase_flutter/supabase_flutter.dart';
import 'attendance_model.dart';
import 'punch_session_model.dart';

class AttendanceRepository {
  final SupabaseClient _client;

  AttendanceRepository(this._client);

  /// Secure server-side punch in RPC
  Future<Map<String, dynamic>> punchIn({
    required String stationId,
    required double lat,
    required double lng,
    required List<double> faceEmbedding,
  }) async {
    final response = await _client.rpc(
      'process_punch_in',
      params: {
        'p_station_id': stationId,
        'p_lat': lat,
        'p_lng': lng,
        'p_face_embedding': faceEmbedding,
      },
    );
    return response as Map<String, dynamic>;
  }

  /// Secure server-side punch out RPC
  Future<Map<String, dynamic>> punchOut({
    required String sessionId,
    required double lat,
    required double lng,
    required List<double> faceEmbedding,
  }) async {
    final response = await _client.rpc(
      'process_punch_out',
      params: {
        'p_session_id': sessionId,
        'p_lat': lat,
        'p_lng': lng,
        'p_face_embedding': faceEmbedding,
      },
    );
    return response as Map<String, dynamic>;
  }

  /// Fetch the user's active in-progress punch session if one exists.
  /// The ID must belong to the authenticated operator; RLS is the final
  /// authorization layer in Supabase.
  Future<PunchSessionModel?> getActiveSession(String operatorId) async {
    if (operatorId.trim().isEmpty) return null;

    final rows = await _client
        .from('punch_sessions')
        .select('*, stations(name)')
        .eq('operator_id', operatorId)
        .isFilter('punch_out_at', null)
        .order('punch_in_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return PunchSessionModel.fromMap(Map<String, dynamic>.from(rows.first));
  }

  /// Check whether the user has already finished their daily shift today
  Future<bool> hasCompletedPunchToday(String userId) async {
    if (userId.trim().isEmpty) return false;

    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Check punch_sessions first (authoritative session records)
      final sessionRecord = await _client
          .from('punch_sessions')
          .select('id')
          .eq('operator_id', userId)
          .gte('punch_in_at', '${today}T00:00:00')
          .lte('punch_in_at', '${today}T23:59:59')
          .filter('punch_out_at', 'not.is', null)
          .limit(1)
          .maybeSingle();

      if (sessionRecord != null) return true;

      // Fallback check on attendance using duty_date and punch_out_time
      final attRecord = await _client
          .from('attendance')
          .select('id')
          .eq('operator_id', userId)
          .gte('punch_in_time', '${today}T00:00:00')
          .lte('punch_in_time', '${today}T23:59:59')
          .filter('punch_out_time', 'not.is', null)
          .limit(1)
          .maybeSingle();

      return attRecord != null;
    } catch (_) {
      return false;
    }
  }

  /// Fetch punch audit history strictly filtered to this individual operator/supervisor
  Future<List<PunchSessionModel>> getPunchHistory(String operatorId) async {
    if (operatorId.trim().isEmpty) return [];

    final response = await _client
        .from('punch_sessions')
        .select('*, stations(name)')
        .eq('operator_id', operatorId)
        .order('punch_in_at', ascending: false)
        .limit(50);

    return (response as List)
        .map((row) => PunchSessionModel.fromMap(row))
        .toList();
  }

  /// Punch history for the authenticated supervisor's own effective scope.
  /// For a reliever, callers must pass the primary supervisor ID.
  Future<List<PunchSessionModel>> getSupervisorOwnPunchHistory(
    String supervisorId,
  ) async {
    if (supervisorId.trim().isEmpty) return [];

    final response = await _client
        .from('punch_sessions')
        .select('*, stations(name)')
        .eq('operator_id', supervisorId)
        .order('punch_in_at', ascending: false)
        .limit(50);

    return (response as List)
        .map((row) => PunchSessionModel.fromMap(row))
        .toList();
  }

  /// Calculates authoritative 4-card summary metrics for operator dashboard:
  /// - Total Duties: Increments for completed shifts
  /// - Earnings: Credited ONLY ONCE per day on regular shifts (OT credits 0.0)
  /// - OT Count: Increments on OT shifts without adding earnings
  /// - Week Offs: Counts explicit WEEK OFF attendance rows
  Future<AttendanceSummaryModel> getOperatorSummaryMetrics(
    String operatorId,
  ) async {
    if (operatorId.trim().isEmpty) {
      return const AttendanceSummaryModel(
        totalDuty: 0,
        earnings: 0.0,
        otDutyCount: 0,
        weekOffCount: 0,
      );
    }

    try {
      // Dashboard metrics are for the current calendar month only.
      // Use duty_date because it is the attendance business date.
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);
      final startDate =
          '${monthStart.year.toString().padLeft(4, '0')}-'
          '${monthStart.month.toString().padLeft(2, '0')}-01';
      final nextMonthDate =
          '${nextMonthStart.year.toString().padLeft(4, '0')}-'
          '${nextMonthStart.month.toString().padLeft(2, '0')}-01';

      // Query attendance and join station's default_fixed_amount.
      // Restrict the result to the current month so the cards reset
      // automatically at each month boundary.
      final attendanceData = await _client
          .from('attendance')
          .select(
            'earnings, is_ot, status, punch_in_time, duty_date, stations(default_fixed_amount)',
          )
          .eq('operator_id', operatorId)
          .gte('duty_date', startDate)
          .lt('duty_date', nextMonthDate)
          .order('duty_date', ascending: true);

      int totalDuties = 0;
      int otCount = 0;
      double totalEarnings = 0.0;
      int weekOffs = 0;

      final Set<String> creditedDates = {};

      for (final row in attendanceData as List) {
        final status = row['status']?.toString().toLowerCase();
        final bool isOt = row['is_ot'] == true;
        final String punchInStr = row['punch_in_time']?.toString() ?? '';
        final String dateStr = punchInStr.length >= 10
            ? punchInStr.substring(0, 10)
            : '';

        if (status == 'present') {
          totalDuties++;

          if (isOt) {
            otCount++;
          } else {
            if (dateStr.isEmpty || !creditedDates.contains(dateStr)) {
              final recordedEarnings =
                  (row['earnings'] as num?)?.toDouble() ?? 0.0;

              // Read supervisor's configured station rate
              final stationMap = row['stations'] as Map<String, dynamic>?;
              final stationRate =
                  (stationMap?['default_fixed_amount'] as num?)?.toDouble() ??
                  0.0;

              // Use recorded earnings if > 0, otherwise use the station's configured amount
              final dutyEarnings = recordedEarnings > 0
                  ? recordedEarnings
                  : stationRate;

              totalEarnings += dutyEarnings;
              if (dateStr.isNotEmpty) creditedDates.add(dateStr);
            }
          }
        } else if (status == 'week_off' || status == 'leave') {
          weekOffs++;
        }
      }

      return AttendanceSummaryModel(
        totalDuty: totalDuties,
        earnings: totalEarnings,
        otDutyCount: otCount,
        weekOffCount: weekOffs,
      );
    } catch (_) {
      return const AttendanceSummaryModel(
        totalDuty: 0,
        earnings: 0.0,
        otDutyCount: 0,
        weekOffCount: 0,
      );
    }
  }
}
