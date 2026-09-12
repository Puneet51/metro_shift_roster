import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/shift_model.dart';
import '../data/shift_repository.dart';

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(SupabaseService.client);
});

/// Supervisor/reliever roster with a single scoped realtime feed.
///
/// The database query remains strictly scoped by effective supervisor. The
/// realtime callbacks only trigger a debounced refresh when the changed row
/// belongs to a shift already in this scope. A new/deleted shift is picked up
/// from the shifts table event itself.
final supervisorShiftsProvider = StreamProvider.autoDispose<List<ShiftModel>>((
  ref,
) async* {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) {
    yield const [];
    return;
  }

  final orgId = user.orgId ?? '';
  final role = user.role.toLowerCase();
  final isAdmin = role == 'admin';
  final supervisorId = isAdmin ? '' : user.effectiveSupervisorId;
  final repo = ref.read(shiftRepositoryProvider);
  final client = SupabaseService.client;

  List<ShiftModel> current = await repo.getSupervisorShifts(
    orgId,
    supervisorId: supervisorId,
  );
  yield current;

  final knownShiftIds = <String>{...current.map((s) => s.id)};
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

  Map<String, dynamic> recordFor(PostgresChangePayload payload, bool old) {
    final record = old ? payload.oldRecord : payload.newRecord;
    return Map<String, dynamic>.from(record);
  }

  final channel = client.channel('roster_scope_${user.id}');

  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'shifts',
    callback: (payload) {
      final newRecord = recordFor(payload, false);
      final oldRecord = recordFor(payload, true);
      final owner = (newRecord['supervisor_id'] ?? oldRecord['supervisor_id'])
          ?.toString();
      final rowOrg = (newRecord['org_id'] ?? oldRecord['org_id'])?.toString();
      if (isAdmin) {
        if (orgId.isEmpty || rowOrg == orgId) scheduleRefresh();
      } else if (owner == supervisorId && (orgId.isEmpty || rowOrg == orgId)) {
        scheduleRefresh();
      }
    },
  );

  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'shift_assignments',
    callback: (payload) {
      final newRecord = recordFor(payload, false);
      final oldRecord = recordFor(payload, true);
      final shiftId = (newRecord['shift_id'] ?? oldRecord['shift_id'])
          ?.toString();
      // Assignment rows do not carry supervisor_id. Use the already-scoped
      // shift IDs so another supervisor's CRUD cannot cause this roster to
      // reload.
      if (shiftId != null && knownShiftIds.contains(shiftId)) {
        scheduleRefresh();
      }
    },
  ).subscribe();

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    refreshEvents.close();
    client.removeChannel(channel);
  });

  await for (final _ in refreshEvents.stream) {
    if (disposed) break;
    current = await repo.getSupervisorShifts(
      orgId,
      supervisorId: supervisorId,
    );
    knownShiftIds
      ..clear()
      ..addAll(current.map((s) => s.id));
    yield current;
  }
});

/// Provides shifts strictly assigned to the logged-in operator.
final operatorShiftsProvider = FutureProvider.autoDispose<List<ShiftModel>>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];

  return ref.watch(shiftRepositoryProvider).getOperatorShifts(user.id);
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
    String? templateId,
    required String startTime,
    required String endTime,
    required double dailyAmount,
    required List<Map<String, dynamic>> rawAssignments,
    String? existingShiftId,
    List<String> clearedOperatingSystemIds = const [],
    List<String> removedOperatingSystemIds = const [],
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

      await _repo.createAndPublishShift(
        orgId: orgId,
        supervisorId: supervisorId,
        stationId: stationId,
        shiftName: shiftName,
        dutyDate: dutyDate,
        templateId: templateId,
        startTime: startTime,
        endTime: endTime,
        dailyAmount: dailyAmount,
        rawAssignments: rawAssignments,
        existingShiftId: existingShiftId,
        clearedOperatingSystemIds: clearedOperatingSystemIds,
        publisherId: user.id,
        publisherName: user.fullName,
        removedOperatingSystemIds: removedOperatingSystemIds,
      );

      _ref.invalidate(supervisorShiftsProvider);
      _ref.invalidate(operatorShiftsProvider);
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
      return ShiftActionNotifier(ref.watch(shiftRepositoryProvider), ref);
    });
