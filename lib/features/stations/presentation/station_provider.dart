import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/station_model.dart';
import '../data/station_repository.dart';

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  return StationRepository(SupabaseService.client);
});

/// Station list with scoped, debounced realtime refresh.
final stationsListProvider = StreamProvider.autoDispose<List<StationModel>>((
  ref,
) async* {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) {
    yield const [];
    return;
  }

  final repo = ref.read(stationRepositoryProvider);
  final orgId = user.orgId ?? '';
  final roleStr = user.role.toString().toLowerCase();
  final isAdmin = roleStr == 'admin';
  final isOperator = roleStr.contains('operator');
  final supervisorId = isAdmin ? '' : user.effectiveSupervisorId;

  List<StationModel> current = await repo.getStations(
    orgId,
    supervisorId: supervisorId,
    isAdmin: isAdmin,
    isOperator: isOperator,
  );
  yield current;

  final knownStationIds = <String>{...current.map((s) => s.id)};
  final refreshEvents = StreamController<void>();
  Timer? debounce;
  bool disposed = false;

  void scheduleRefresh() {
    if (disposed) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 180), () {
      if (!disposed && !refreshEvents.isClosed) refreshEvents.add(null);
    });
  }

  final channel = SupabaseService.client.channel('stations_scope_${user.id}');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stations',
        callback: (payload) {
          final row = payload.newRecord.isNotEmpty
              ? payload.newRecord
              : payload.oldRecord;
          final rowId = row['id']?.toString();
          final rowOrg = row['org_id']?.toString();
          final owner = row['supervisor_id']?.toString();
          if (rowId != null && knownStationIds.contains(rowId)) {
            scheduleRefresh();
            return;
          }
          if (orgId.isNotEmpty && rowOrg != orgId) return;
          if (isAdmin || isOperator || owner == supervisorId) {
            scheduleRefresh();
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    refreshEvents.close();
    SupabaseService.client.removeChannel(channel);
  });

  await for (final _ in refreshEvents.stream) {
    if (disposed) break;
    current = await repo.getStations(
      orgId,
      supervisorId: supervisorId,
      isAdmin: isAdmin,
      isOperator: isOperator,
    );
    knownStationIds
      ..clear()
      ..addAll(current.map((s) => s.id));
    yield current;
  }
});

final stationsProvider = stationsListProvider;

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
    required double fixedAmount,
    required List<String> tomSystems,
    required List<Map<String, String>> shiftTemplates,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');
      final orgId = user.orgId ?? '';
      final supervisorId = user.effectiveSupervisorId;
      if (supervisorId.isEmpty) {
        throw Exception('No supervisor scope available');
      }
      if (user.role.toLowerCase().contains('operator') ||
          user.role.toLowerCase() == 'admin') {
        throw Exception('Only supervisors and relievers can manage stations');
      }

      await _repo.saveStation(
        stationId: stationId,
        orgId: orgId,
        supervisorId: supervisorId,
        name: name,
        latitude: latitude,
        longitude: longitude,
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
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');
      if (user.role.toLowerCase().contains('operator') ||
          user.role.toLowerCase() == 'admin') {
        throw Exception('Only supervisors and relievers can delete stations');
      }
      await _repo.deleteStation(
        stationId: stationId,
        orgId: user.orgId ?? '',
        supervisorId: user.effectiveSupervisorId,
      );
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
