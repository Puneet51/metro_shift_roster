import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/attendance_model.dart';
import '../data/attendance_repository.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(SupabaseService.client);
});

final operatorAttendanceProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];
  return ref.watch(attendanceRepositoryProvider).getMyAttendance(user.id);
});

final operatorSummaryMetricsProvider =
    FutureProvider.autoDispose<AttendanceSummaryModel>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || user.role != 'operator') {
    return const AttendanceSummaryModel();
  }
  return ref.watch(attendanceRepositoryProvider).getOperatorSummaryMetrics(user.id);
});
