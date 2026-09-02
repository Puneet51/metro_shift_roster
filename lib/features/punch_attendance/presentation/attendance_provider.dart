import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';

// 1. Active Punch Session for Operator
final activePunchSessionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null) return null;

      final response = await SupabaseService.client
          .from('attendance')
          .select('*, stations(*), shifts(*)')
          .eq('operator_id', user.id)
          .filter('punch_out_time', 'is', 'null')
          .order('created_at', ascending: false)
          .maybeSingle();

      return response;
    });

// 2. Punch Audit List Provider
// 2. Punch Audit List Provider (Filtered by User Role)
final punchAuditListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null) return [];

      var query = SupabaseService.client
          .from('attendance')
          .select('*, stations(name), profiles(full_name)');

      // Operators only see their own punch records; supervisors/admins see all
      if (user.role == 'operator') {
        query = query.eq('operator_id', user.id);
      } else {
        query = query.eq(
          'org_id',
          user.orgId ?? '00000000-0000-0000-0000-000000000001',
        );
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(30);

      return List<Map<String, dynamic>>.from(response as List);
    });

// 3. Operator Summary Metrics Provider
final operatorSummaryMetricsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null) return {};

      final response = await SupabaseService.client.rpc(
        'get_operator_dashboard_overview',
        params: {
          'p_operator_id': user.id,
          'p_org_id': user.orgId ?? '00000000-0000-0000-0000-000000000001',
        },
      );

      return (response as Map<String, dynamic>?) ?? {};
    });

// 4. Attendance StateNotifier
class AttendanceNotifier extends StateNotifier<AsyncValue<void>> {
  AttendanceNotifier() : super(const AsyncValue.data(null));

  Future<void> punchOut({
    required String operatorId,
    required String shiftId,
    required String dutyDate,
    required double latitude,
    required double longitude,
  }) async {
    state = const AsyncValue.loading();
    try {
      final client = SupabaseService.client;
      final nowUtc = DateTime.now().toIso8601String();

      final existing = await client
          .from('attendance')
          .select('id')
          .eq('operator_id', operatorId)
          .eq('shift_id', shiftId)
          .eq('duty_date', dutyDate)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('attendance')
            .update({
              'punch_out_time': nowUtc,
              'punch_out_lat': latitude,
              'punch_out_lng': longitude,
              'status': 'completed',
              'updated_at': nowUtc,
            })
            .eq('id', existing['id']);
      } else {
        await client.from('attendance').insert({
          'operator_id': operatorId,
          'shift_id': shiftId,
          'duty_date': dutyDate,
          'punch_out_time': nowUtc,
          'punch_out_lat': latitude,
          'punch_out_lng': longitude,
          'status': 'completed',
        });
      }

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final attendanceNotifierProvider =
    StateNotifierProvider<AttendanceNotifier, AsyncValue<void>>((ref) {
      return AttendanceNotifier();
    });
