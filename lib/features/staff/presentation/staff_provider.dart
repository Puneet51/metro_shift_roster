import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/operator_model.dart';
import '../data/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(SupabaseService.client);
});

final staffListProvider = FutureProvider<List<OperatorModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];

  final orgId = user.orgId ?? '';
  final isAdmin = user.role == 'admin';
  final supervisorId = isAdmin
      ? ''
      : (user.role == 'supervisor' ? user.id : user.effectiveSupervisorId);

  if (!isAdmin && supervisorId.isEmpty) return [];

  return ref
      .watch(staffRepositoryProvider)
      .getOperators(orgId, supervisorId: supervisorId);
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
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');

      final orgId = user.orgId ?? '';
      final supervisorId = user.role == 'supervisor'
          ? user.id
          : user.effectiveSupervisorId;

      await _repo.addOperator(
        orgId: orgId,
        supervisorId: supervisorId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        biometricId: biometricId,
        companyId: companyId,
        bmrclId: bmrclId,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateOperator({
    required String operatorId,
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repo.updateOperator(
        operatorId: operatorId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        biometricId: biometricId,
        companyId: companyId,
        bmrclId: bmrclId,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteOperator(String operatorId) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null) throw Exception('User not logged in');

      final supervisorId = user.role == 'supervisor'
          ? user.id
          : user.effectiveSupervisorId;

      await _repo.deleteOperator(
        operatorId: operatorId,
        supervisorId: supervisorId,
      );
      _ref.invalidate(staffListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final staffActionNotifierProvider =
    StateNotifierProvider<StaffActionNotifier, AsyncValue<void>>((ref) {
      return StaffActionNotifier(ref.watch(staffRepositoryProvider), ref);
    });
