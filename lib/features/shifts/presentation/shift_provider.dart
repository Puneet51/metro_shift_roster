import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/shift_model.dart';
import '../data/shift_repository.dart';

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(SupabaseService.client);
});

final supervisorShiftsProvider = FutureProvider.autoDispose<List<ShiftModel>>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || user.orgId == null) return [];
  return ref.watch(shiftRepositoryProvider).getSupervisorShifts(user.orgId!);
});

class ShiftActionNotifier extends StateNotifier<AsyncValue<void>> {
  final ShiftRepository _repo;
  final Ref _ref;

  ShiftActionNotifier(this._repo, this._ref)
    : super(const AsyncValue.data(null));

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
      final user = _ref.read(authNotifierProvider).user!;
      await _repo.createAndPublishShift(
        orgId: user.orgId!,
        supervisorId: user.id,
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
}

final shiftActionNotifierProvider =
    StateNotifierProvider<ShiftActionNotifier, AsyncValue<void>>((ref) {
      return ShiftActionNotifier(ref.watch(shiftRepositoryProvider), ref);
    });
