import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(SupabaseService.client);
});

final adminSupervisorsListProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final user = ref.watch(authNotifierProvider).user;
    final orgId = user?.orgId ?? '00000000-0000-0000-0000-000000000001';
    return ref.watch(adminRepositoryProvider).getSupervisors(orgId);
  },
);

class AdminActionNotifier extends StateNotifier<AsyncValue<void>> {
  final AdminRepository _adminRepo;
  final Ref _ref;

  AdminActionNotifier(this._adminRepo, this._ref)
    : super(const AsyncValue.data(null));

  Future<void> deleteSupervisor(String supervisorId) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(authNotifierProvider).user;
      if (user == null || user.role != 'admin') {
        throw Exception(
          'Unauthorized: Only an Administrator can delete a supervisor.',
        );
      }

      await _adminRepo.deleteSupervisor(
        supervisorId: supervisorId,
        adminId: user.id,
      );

      _ref.invalidate(adminSupervisorsListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final adminActionNotifierProvider =
    StateNotifierProvider<AdminActionNotifier, AsyncValue<void>>((ref) {
      return AdminActionNotifier(ref.watch(adminRepositoryProvider), ref);
    });
