import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/station_model.dart';
import '../data/station_repository.dart';

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  return StationRepository(SupabaseService.client);
});

final stationsListProvider = StreamProvider.autoDispose<List<StationModel>>((
  ref,
) async* {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) {
    yield [];
    return;
  }

  final repo = ref.watch(stationRepositoryProvider);
  final orgId = user.orgId ?? '';
  final isAdmin = user.role == 'admin';
  final supervisorId = isAdmin
      ? ''
      : (user.role == 'supervisor' ? user.id : user.effectiveSupervisorId);

  final initialData = await repo.getStations(
    orgId,
    supervisorId: supervisorId,
    isAdmin: isAdmin,
  );
  yield initialData;

  final client = SupabaseService.client;
  final channel = client
      .channel('public:stations_feed_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stations',
        callback: (_) {
          ref.invalidateSelf();
        },
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
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
      if (user == null) throw Exception('User not logged in');

      final orgId = user.orgId ?? '';
      final supervisorId = user.role == 'supervisor'
          ? user.id
          : user.effectiveSupervisorId;

      await _repo.saveStation(
        stationId: stationId,
        orgId: orgId,
        supervisorId: supervisorId,
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
