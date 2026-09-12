import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/operator_model.dart';
import '../data/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(SupabaseService.client);
});

/// Staff list with scoped realtime refresh. CRUD changes appear without a
/// manual refresh, while every read remains restricted to the effective
/// supervisor scope.
final staffListProvider = StreamProvider.autoDispose<List<OperatorModel>>((
  ref,
) async* {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) {
    yield const [];
    return;
  }

  final orgId = user.orgId ?? '';
  final isAdmin = user.role.toLowerCase() == 'admin';
  final supervisorId = isAdmin ? '' : user.effectiveSupervisorId;
  if (!isAdmin && supervisorId.isEmpty) {
    yield const [];
    return;
  }

  final repo = ref.read(staffRepositoryProvider);
  final client = SupabaseService.client;
  List<OperatorModel> current = await repo.getOperators(
    orgId,
    supervisorId: supervisorId,
  );
  yield current;

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

  final channel = client.channel('staff_scope_${user.id}');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (payload) {
          final newRecord = payload.newRecord;
          final oldRecord = payload.oldRecord;
          final row = newRecord.isNotEmpty ? newRecord : oldRecord;
          final role = row['role']?.toString().toLowerCase();
          final rowOrg = row['org_id']?.toString();
          final parent = row['parent_supervisor_id']?.toString();
          if (role != 'operator') return;
          if (orgId.isNotEmpty && rowOrg != orgId) return;
          if (isAdmin || parent == supervisorId) scheduleRefresh();
        },
      )
      .subscribe();

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    refreshEvents.close();
    client.removeChannel(channel);
  });

  await for (final _ in refreshEvents.stream) {
    if (disposed) break;
    current = await repo.getOperators(orgId, supervisorId: supervisorId);
    yield current;
  }
});

class StaffActionNotifier extends StateNotifier<AsyncValue<void>> {
  final StaffRepository _repo;
  final Ref _ref;

  StaffActionNotifier(this._repo, this._ref)
    : super(const AsyncValue.data(null));

  Future<void> addOperator({
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
    String? fatherName,
    String? empCode,
    String? esiNo,
    String? uanNo,
    String? doj,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');
      final orgId = user.orgId ?? '';
      if (user.role == 'admin') {
        throw Exception('Admins must use the admin staff-management flow');
      }
      final supervisorId = user.effectiveSupervisorId;
      if (supervisorId.isEmpty) {
        throw Exception('No supervisor scope available');
      }

      await _repo.addOperator(
        orgId: orgId,
        supervisorId: supervisorId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        biometricId: biometricId,
        companyId: companyId,
        bmrclId: bmrclId,
        fatherName: fatherName,
        empCode: empCode,
        esiNo: esiNo,
        uanNo: uanNo,
        doj: doj,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> updateOperator({
    required String operatorId,
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
    String? fatherName,
    String? empCode,
    String? esiNo,
    String? uanNo,
    String? doj,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');
      await _repo.updateOperator(
        operatorId: operatorId,
        supervisorId: user.effectiveSupervisorId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        biometricId: biometricId,
        companyId: companyId,
        bmrclId: bmrclId,
        fatherName: fatherName,
        empCode: empCode,
        esiNo: esiNo,
        uanNo: uanNo,
        doj: doj,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deleteOperator(String operatorId) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');
      await _repo.deleteOperator(
        operatorId: operatorId,
        supervisorId: user.effectiveSupervisorId,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final staffActionNotifierProvider =
    StateNotifierProvider<StaffActionNotifier, AsyncValue<void>>((ref) {
      return StaffActionNotifier(ref.watch(staffRepositoryProvider), ref);
    });
