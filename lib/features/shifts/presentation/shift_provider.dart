import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/shift_model.dart';
import '../data/shift_repository.dart';

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(SupabaseService.client); //[cite: 8]
});

// Provides shifts strictly isolated to the logged-in supervisor
final supervisorShiftsProvider = FutureProvider.autoDispose<List<ShiftModel>>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).user; //[cite: 8]
  if (user == null) return []; //[cite: 8]

  final orgId = user.orgId ?? '';
  // Enforce strict supervisor filtering; admins can pass an empty string to view all
  final supervisorId = (user.role == 'admin') ? '' : user.effectiveSupervisorId;

  return ref
      .watch(shiftRepositoryProvider)
      .getSupervisorShifts(orgId, supervisorId: supervisorId);
});

// Provides shifts strictly assigned to the logged-in operator
final operatorShiftsProvider = FutureProvider.autoDispose<List<ShiftModel>>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];

  return ref.watch(shiftRepositoryProvider).getOperatorShifts(user.id);
});

class ShiftActionNotifier extends StateNotifier<AsyncValue<void>> {
  final ShiftRepository _repo; //[cite: 8]
  final Ref _ref; //[cite: 8]

  ShiftActionNotifier(this._repo, this._ref)
    : super(const AsyncValue.data(null)); //[cite: 8]

  Future<void> publishShift({
    required String stationId,
    required String shiftName,
    required String dutyDate,
    required String startTime,
    required String endTime,
    required double dailyAmount,
    required List<Map<String, dynamic>> rawAssignments,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');

      final orgId = user.orgId ?? '';
      final supervisorId = user.role == 'supervisor'
          ? user.id
          : user.effectiveSupervisorId;

      await _repo.createAndPublishShift(
        orgId: orgId,
        supervisorId: supervisorId,
        stationId: stationId,
        shiftName: shiftName,
        dutyDate: dutyDate,
        startTime: startTime,
        endTime: endTime,
        dailyAmount: dailyAmount,
        rawAssignments: rawAssignments,
      );

      _ref.invalidate(supervisorShiftsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteShift(String shiftId) async {
    state = const AsyncValue.loading();
    try {
      await _repo.deleteShift(shiftId);
      _ref.invalidate(supervisorShiftsProvider);
      _ref.invalidate(operatorShiftsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final shiftActionNotifierProvider =
    StateNotifierProvider<ShiftActionNotifier, AsyncValue<void>>((ref) {
      return ShiftActionNotifier(
        ref.watch(shiftRepositoryProvider),
        ref,
      ); //[cite: 8]
    });
