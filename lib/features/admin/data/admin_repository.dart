import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRepository {
  final SupabaseClient _client;

  AdminRepository(this._client);

  /// Fetches supervisors with specific staff counts and nested relievers
  Future<List<Map<String, dynamic>>> getSupervisors(String orgId) async {
    final res = await _client.rpc(
      'get_org_supervisors_overview',
      params: orgId.isNotEmpty ? {'p_org_id': orgId} : {},
    );

    if (res is! List) {
      throw Exception('Invalid supervisor overview response');
    }

    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Creates a supervisor with a strictly 4-digit temporary PIN and pre-provisions auth.users
  Future<void> addSupervisor({
    required String orgId,
    required String fullName,
    required String phoneNumber,
    String? email,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final res = await _client.rpc(
      'create_native_supervisor',
      params: {
        'p_full_name': fullName.trim(),
        'p_phone_number': cleanPhone,
        if (orgId.isNotEmpty) 'p_org_id': orgId,
      },
    );

    final data = res as Map<String, dynamic>;

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to register supervisor');
    }
  }

  /// Adds a dedicated reliever linked to a primary supervisor with pre-provisioned auth.users
  Future<void> addSupervisorReliever({
    required String supervisorId,
    required String fullName,
    required String phoneNumber,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final res = await _client.rpc(
      'add_supervisor_reliever',
      params: {
        'p_supervisor_id': supervisorId,
        'p_full_name': fullName.trim(),
        'p_phone_number': cleanPhone,
      },
    );

    final data = res as Map<String, dynamic>;

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to add reliever');
    }
  }

  /// Admin-managed PIN Reset (Returns 4-digit temporary PIN)
  Future<String> adminGenerateAndSendSupervisorPin({
    required String supervisorId,
    required String adminId,
  }) async {
    final res = await _client.rpc(
      'admin_reset_supervisor_pin',
      params: {'p_supervisor_id': supervisorId, 'p_admin_id': adminId},
    );

    final result = res as Map<String, dynamic>;
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to reset supervisor PIN');
    }

    return result['temp_pin'].toString();
  }

  Future<void> updateSupervisor({
    required String supervisorId,
    required String fullName,
    required String phoneNumber,
    String? email,
    required bool isActive,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          'phone_number': cleanPhone,
          'email': email?.trim(),
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', supervisorId);
  }

  Future<void> deleteSupervisor({
    required String supervisorId,
    required String adminId,
  }) async {

    final res = await _client.rpc(
      'delete_supervisor_strict',
      params: {'p_supervisor_id': supervisorId, 'p_admin_id': adminId},
    );

    final data = res as Map<String, dynamic>;

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to delete supervisor');
    }


  }

  Future<void> setAppVersionConfig({
    required String platform,
    required String latestVersion,
    required String minVersion,
    required String updateUrl,
    required String releaseNotes,
    required bool forceUpdate,
  }) async {
    await _client.from('app_versions').upsert({
      'platform': platform,
      'latest_version': latestVersion,
      'min_required_version': minVersion,
      'update_url': updateUrl,
      'release_notes': releaseNotes,
      'force_update': forceUpdate,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'platform');
  }
}
