import 'package:supabase_flutter/supabase_flutter.dart';
import 'attendance_model.dart';

class AttendanceRepository {
  final SupabaseClient _client;

  AttendanceRepository(this._client);

  Future<List<Map<String, dynamic>>> getMyAttendance(String operatorId) async {
    if (operatorId.trim().isEmpty) return [];
    // Attendance rows and the assignment roster are independent reads. Run
    // them together so the attendance screen does not wait twice for the
    // network.
    final results = await Future.wait<dynamic>([
      _client
          .from('attendance')
          .select('id, duty_date, status, is_ot, earnings, station_id, shift_id, stations(name), shifts(shift_name, start_time, end_time)')
          .eq('operator_id', operatorId)
          .order('duty_date', ascending: false)
          .limit(100),
      _client.rpc(
        'get_my_operator_roster',
        params: {'p_operator_id': operatorId},
      ),
    ]);

    final rows = <Map<String, dynamic>>[
      ...List<Map<String, dynamic>>.from(results[0] as List),
    ];
    final knownShiftIds = rows
        .map((r) => r['shift_id']?.toString())
        .whereType<String>()
        .toSet();

    // Completed assignments are the source of truth for PRESENT. This also
    // makes the log correct even before the scheduled DB finalizer runs.
    final assigned = results[1];
    final now = DateTime.now();
    for (final raw in (assigned as List?) ?? const []) {
      final m = Map<String, dynamic>.from(raw as Map);
      final shiftId = m['shift_id']?.toString() ?? '';
      final dateStr = m['duty_date']?.toString() ?? '';
      if (shiftId.isEmpty || knownShiftIds.contains(shiftId) || dateStr.isEmpty) continue;
      final d = DateTime.tryParse(dateStr);
      if (d == null) continue;
      final completedAt = _completedAt(d, m['start_time']?.toString(), m['end_time']?.toString());
      if (now.isBefore(completedAt)) continue;
      rows.add({
        'id': shiftId,
        'duty_date': dateStr,
        'status': 'present',
        'is_ot': m['is_ot'] == true,
        'earnings': ((m['daily_amount'] as num?)?.toDouble() ?? 0) * (m['is_ot'] == true ? 2 : 1),
        'station_id': m['station_id'],
        'shift_id': shiftId,
        'stations': {'name': m['station_name']?.toString() ?? 'Station'},
        'shifts': {
          'shift_name': m['shift_name']?.toString() ?? 'Duty',
          'start_time': m['start_time']?.toString() ?? '',
          'end_time': m['end_time']?.toString() ?? '',
        },
      });
      knownShiftIds.add(shiftId);
    }
    rows.sort((a, b) => (b['duty_date']?.toString() ?? '').compareTo(a['duty_date']?.toString() ?? ''));
    return rows;
  }

  DateTime _completedAt(DateTime dutyDate, String? start, String? end) {
    final sp = (start ?? '00:00:00').split(':');
    final ep = (end ?? '00:00:00').split(':');
    final sh = int.tryParse(sp.isNotEmpty ? sp[0] : '0') ?? 0;
    final sm = int.tryParse(sp.length > 1 ? sp[1] : '0') ?? 0;
    final eh = int.tryParse(ep.isNotEmpty ? ep[0] : '0') ?? 0;
    final em = int.tryParse(ep.length > 1 ? ep[1] : '0') ?? 0;
    var result = DateTime(dutyDate.year, dutyDate.month, dutyDate.day, eh, em);
    if (eh * 60 + em < sh * 60 + sm) result = result.add(const Duration(days: 1));
    return result;
  }


  Future<List<Map<String, dynamic>>> getCompletedDutyOperators({
    required String stationId,
    required DateTime selectedMonth,
  }) async {
    if (stationId.trim().isEmpty) return [];
    final start = '${selectedMonth.year.toString().padLeft(4, '0')}-${selectedMonth.month.toString().padLeft(2, '0')}-01';
    final next = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    final nextDate = '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}-01';
    final rows = await _client.from('shift_assignments').select('''
      operator_id, is_ot,
      shifts!inner(id, org_id, station_id, duty_date, shift_name, start_time, end_time, is_published, daily_amount),
      profiles!inner(id, full_name, role)
    ''').eq('station_id', stationId).eq('shifts.is_published', true)
      .eq('profiles.role', 'operator').gte('shifts.duty_date', start).lt('shifts.duty_date', nextDate);
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final shift = m['shifts']; final profile = m['profiles'];
      if (shift is! Map || profile is! Map) continue;
      final d = DateTime.tryParse(shift['duty_date']?.toString() ?? '');
      if (d == null || now.isBefore(_completedAt(d, shift['start_time']?.toString(), shift['end_time']?.toString()))) continue;
      result.add({
        'operator_id': m['operator_id'], 'operator_name': profile['full_name']?.toString() ?? 'Operator',
        'duty_date': shift['duty_date']?.toString() ?? '', 'shift_name': shift['shift_name']?.toString() ?? 'Duty',
        'start_time': shift['start_time']?.toString() ?? '', 'end_time': shift['end_time']?.toString() ?? '', 'is_ot': m['is_ot'] == true,
      });
    }
    result.sort((a,b) => (b['duty_date']?.toString() ?? '').compareTo(a['duty_date']?.toString() ?? ''));
    return result;
  }


  Future<int> getCompletedDutyCount({required String stationId, required DateTime selectedMonth}) async {
    return (await getCompletedDutyOperators(stationId: stationId, selectedMonth: selectedMonth)).length;
  }


  Future<AttendanceSummaryModel> getOperatorSummaryMetrics(String operatorId) async {
    if (operatorId.trim().isEmpty) return const AttendanceSummaryModel();
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final start = '${monthStart.year.toString().padLeft(4, '0')}-${monthStart.month.toString().padLeft(2, '0')}-01';
      final end = '${nextMonth.year.toString().padLeft(4, '0')}-${nextMonth.month.toString().padLeft(2, '0')}-01';
      final results = await Future.wait<dynamic>([
        _client.rpc('get_my_operator_roster', params: {'p_operator_id': operatorId}),
        _client
            .from('attendance')
            .select('status, duty_date')
            .eq('operator_id', operatorId)
            .gte('duty_date', start)
            .lt('duty_date', end),
      ]);
      final rows = results[0];
      int duties = 0, ot = 0, weekOff = 0, absent = 0;
      double earnings = 0;
      final completedShiftIds = <String>{};
      for (final raw in (rows as List?) ?? const []) {
        final m = Map<String, dynamic>.from(raw as Map);
        final date = m['duty_date']?.toString() ?? '';
        if (date.compareTo(start) < 0 || date.compareTo(end) >= 0) continue;
        final d = DateTime.tryParse(date); if (d == null) continue;
        if (now.isBefore(_completedAt(d, m['start_time']?.toString(), m['end_time']?.toString()))) continue;
        final id = m['shift_id']?.toString() ?? '';
        if (!completedShiftIds.add(id)) continue;
        if (m['is_ot'] == true) {
          ot++;
          earnings += ((m['daily_amount'] as num?)?.toDouble() ?? 0) * 2;
        } else {
          duties++;
          earnings += (m['daily_amount'] as num?)?.toDouble() ?? 0;
        }
      }
      // Historical explicit week-off/absent records remain counted, but a
      // future present record can never inflate metrics.
      final att = results[1];
      for (final raw in att as List) {
        final m = Map<String, dynamic>.from(raw as Map); final st = m['status']?.toString().toLowerCase();
        if (st == 'week_off') weekOff++; else if (st == 'absent') absent++;
      }
      return AttendanceSummaryModel(totalDuty: duties, earnings: earnings, otDutyCount: ot, weekOffCount: weekOff, absentCount: absent);
    } catch (_) { return const AttendanceSummaryModel(); }
  }

}
