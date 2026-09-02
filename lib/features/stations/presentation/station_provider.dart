import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/station_model.dart';
import '../data/station_repository.dart';

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  return StationRepository(SupabaseService.client);
});

final stationsListProvider = FutureProvider<List<StationModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || user.orgId == null) return [];
  return ref.watch(stationRepositoryProvider).getStations(user.orgId!);
});

class StationActionNotifier extends StateNotifier<AsyncValue<void>> {
  final StationRepository _repo;
  final Ref _ref;

  StationActionNotifier(this._repo, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> saveStation({
    String? stationId,
    required String name,
    required double latitude,
    required double longitude,
    required int punchRadius,
    required double fixedAmount,
    required List<String> tomSystems,
    required List<Map<String, String>> shiftTemplates,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null || user.orgId == null) {
        throw Exception('User session invalid or organization not found.');
      }

      await _repo.saveStation(
        stationId: stationId,
        orgId: user.orgId!,
        supervisorId: user.id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        punchRadius: punchRadius,
        fixedAmount: fixedAmount,
        tomSystems: tomSystems,
        shiftTemplates: shiftTemplates,
      );
      _ref.invalidate(stationsListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteStation(String stationId) async {
    state = const AsyncValue.loading();
    try {
      await _repo.deleteStation(stationId);
      _ref.invalidate(stationsListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final stationActionNotifierProvider =
    StateNotifierProvider<StationActionNotifier, AsyncValue<void>>((ref) {
  return StationActionNotifier(ref.watch(stationRepositoryProvider), ref);
});
