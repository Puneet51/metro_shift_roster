import 'package:supabase_flutter/supabase_flutter.dart';
import 'attendance_model.dart';

class AttendanceRepository {
  final SupabaseClient _client;

  AttendanceRepository(this._client);

  /// Trigger secure server-side punch in RPC
  Future<Map<String, dynamic>> punchIn({
    required String stationId,
    required double lat,
    required double lng,
    required bool isFaceVerified,
  }) async {
    final response = await _client.rpc('process_punch_in', params: {
      'p_station_id': stationId,
      'p_lat': lat,
      'p_lng': lng,
      'p_is_face_verified': isFaceVerified,
    });
    return response as Map<String, dynamic>;
  }

  /// Trigger secure server-side punch out RPC
  Future<Map<String, dynamic>> punchOut({
    required String sessionId,
    required double lat,
    required double lng,
    required bool isFaceVerified,
  }) async {
    final response = await _client.rpc('process_punch_out', params: {
      'p_session_id': sessionId,
      'p_lat': lat,
      'p_lng': lng,
      'p_is_face_verified': isFaceVerified,
    });
    return response as Map<String, dynamic>;
  }

  /// Fetch the user's active in-progress punch session if one exists
  Future<PunchSessionModel?> getActiveSession(String operatorId) async {
    final data = await _client
        .from('punch_sessions')
        .select('*, stations(name)')
        .eq('operator_id', operatorId)
        .isFilter('punch_out_at', null)
        .order('punch_in_at', ascending: false)
        .maybeSingle();

    return data != null ? PunchSessionModel.fromMap(data) : null;
  }

  /// Fetch punch audit history for supervisor and operator audit tabs
  Future<List<PunchSessionModel>> getPunchHistory(String operatorId) async {
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

  /// Calculates authoritative 4-card summary metrics for operator dashboard
  Future<AttendanceSummaryModel> getOperatorSummaryMetrics(
      String operatorId) async {
    final attendanceData = await _client
        .from('attendance')
        .select('earnings, is_ot, status')
        .eq('operator_id', operatorId);

    int totalDuties = 0;
    int otCount = 0;
    double totalEarnings = 0.0;
    int weekOffs = 0;

    for (final row in attendanceData as List) {
      if (row['status'] == 'present') {
        totalDuties++;
        totalEarnings += (row['earnings'] as num?)?.toDouble() ?? 0.0;
        if (row['is_ot'] == true) {
          otCount++;
        }
      } else if (row['status'] == 'absent') {
        weekOffs++;
      }
    }

    return AttendanceSummaryModel(
      totalDuty: totalDuties,
      earnings: totalEarnings,
      otDutyCount: otCount,
      weekOffCount: weekOffs,
    );
  }
}
