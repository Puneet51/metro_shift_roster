import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/operator_model.dart';
import '../data/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(SupabaseService.client);
});

// Change:
final staffListProvider = FutureProvider<List<OperatorModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || user.orgId == null) return [];

  final res = await SupabaseService.client
      .from('profiles')
      .select()
      .eq('org_id', user.orgId!)
      .order('full_name', ascending: true);

  return (res as List).map((e) => OperatorModel.fromJson(e)).toList();
});

class StaffActionNotifier extends StateNotifier<AsyncValue<void>> {
  final StaffRepository _repo;
  final Ref _ref;

  StaffActionNotifier(this._repo, this._ref)
    : super(const AsyncValue.data(null));

  Future<void> addOperator(String fullName, String phoneNumber) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      final orgId = user?.orgId ?? '00000000-0000-0000-0000-000000000001';
      await _repo.addOperator(
        orgId: orgId,
        fullName: fullName,
        phoneNumber: phoneNumber,
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
      await _repo.deleteOperator(operatorId);
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
