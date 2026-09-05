import 'package:supabase_flutter/supabase_flutter.dart';
import 'operator_model.dart';

class StaffRepository {
  final SupabaseClient _client;

  StaffRepository(this._client);

  /// Fetches operators strictly isolated to the calling supervisor
  Future<List<OperatorModel>> getOperators(
    String orgId, {
    required String supervisorId,
  }) async {
    var query = _client
        .from('profiles')
        .select('''
          id,
          org_id,
          full_name,
          phone_number,
          role,
          emp_code,
          company_id,
          biometric_id,
          bmrcl_id,
          parent_supervisor_id,
          is_reliever,
          is_active,
          has_pin,
          created_at
        ''')
        .eq('parent_supervisor_id', supervisorId)
        .eq('is_active', true)
        .eq('role', 'tom_operator');

    if (orgId.isNotEmpty) {
      query = query.or('org_id.eq.$orgId,org_id.is.null');
    }

    final response = await query.order('full_name', ascending: true);
    final operatorList = response as List;

    if (operatorList.isEmpty) {
      return [];
    }

    final operatorIds = operatorList
        .map((row) => row['id'].toString())
        .toList();

    final attendanceData = await _client
        .from('attendance')
        .select('operator_id')
        .filter('operator_id', 'in', operatorIds)
        .eq('status', 'absent');

    final Map<String, int> weekOffMap = {};
    for (final att in attendanceData as List) {
      final opId = att['operator_id']?.toString() ?? '';
      weekOffMap[opId] = (weekOffMap[opId] ?? 0) + 1;
    }

    return operatorList.map((row) {
      final id = row['id'].toString();
      return OperatorModel.fromMap(
        row as Map<String, dynamic>,
        weekOffs: weekOffMap[id] ?? 0,
      );
    }).toList();
  }

  /// Adds an operator natively in auth.users and profiles
  Future<void> addOperator({
    required String orgId,
    required String fullName,
    required String phoneNumber,
    required String supervisorId,
    String? biometricId,
    String? companyId,
    String? bmrclId,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final res = await _client.rpc(
      'create_native_staff_member',
      params: {
        'p_full_name': fullName.trim(),
        'p_phone_number': cleanPhone,
        'p_role': 'tom_operator',
        if (orgId.isNotEmpty) 'p_org_id': orgId,
        'p_supervisor_id': supervisorId,
        'p_bmrcl_id': bmrclId?.trim(),
        'p_company_id': companyId?.trim(),
        'p_biometric_id': biometricId?.trim(),
      },
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to register operator');
    }
  }

  /// Updates an operator
  Future<void> updateOperator({
    required String operatorId,
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          'phone_number': cleanPhone,
          'biometric_id': biometricId?.trim(),
          'company_id': companyId?.trim(),
          'bmrcl_id': bmrclId?.trim(),
          'emp_code': companyId?.trim() ?? bmrclId?.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', operatorId);
  }

  /// Deactivates an operator strictly if owned by the calling supervisor or admin
  Future<void> deleteOperator({
    required String operatorId,
    required String supervisorId,
  }) async {
    final res = await _client.rpc(
      'delete_staff_operator_strict',
      params: {'p_operator_id': operatorId, 'p_supervisor_id': supervisorId},
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to delete operator');
    }
  }
}
