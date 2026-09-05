import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AdminRepository {
  final SupabaseClient _client;

  AdminRepository(this._client);

  Future<List<Map<String, dynamic>>> getSupervisors(String orgId) async {
    try {
      final res = await _client.rpc(
        'get_org_supervisors_overview',
        params: {'p_org_id': orgId},
      );
      if (res != null && res is List) {
        return res
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) => e['role'] == 'supervisor')
            .toList();
      }
    } catch (_) {
      final fallbackRes = await _client
          .from('profiles')
          .select()
          .eq('role', 'supervisor')
          .order('full_name', ascending: true);

      final totalStations =
          (await _client.from('stations').select('id') as List).length;
      final totalOperators =
          (await _client
                      .from('profiles')
                      .select('id')
                      .eq('role', 'tom_operator')
                  as List)
              .length;

      final List<Map<String, dynamic>> list = [];
      for (final row in fallbackRes as List) {
        final r = Map<String, dynamic>.from(row as Map<String, dynamic>);
        r['total_stations'] = totalStations;
        r['total_operators'] = totalOperators;
        list.add(r);
      }
      return list;
    }
    return [];
  }

  Future<void> addSupervisor({
    required String orgId,
    required String fullName,
    required String phoneNumber,
    String? email,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    try {
      final res = await _client.rpc(
        'create_native_staff_member',
        params: {
          'p_full_name': fullName.trim(),
          'p_phone_number': cleanPhone,
          'p_role': 'supervisor',
          if (orgId.isNotEmpty) 'p_org_id': orgId,
        },
      );

      final data = res as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to register supervisor');
      }
    } catch (_) {
      await _client.from('profiles').insert({
        'id': const Uuid().v4(),
        'org_id': orgId,
        'role': 'supervisor',
        'full_name': fullName.trim(),
        'phone_number': cleanPhone,
        'email': email?.trim(),
        'pin_hash': '1234',
        'has_pin': true,
        'is_active': true,
      });
    }
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
