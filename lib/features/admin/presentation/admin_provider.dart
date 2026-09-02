import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(SupabaseService.client);
});

final adminSupervisorsListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  final orgId = user?.orgId ?? '00000000-0000-0000-0000-000000000001';
  return ref.watch(adminRepositoryProvider).getSupervisors(orgId);
});
