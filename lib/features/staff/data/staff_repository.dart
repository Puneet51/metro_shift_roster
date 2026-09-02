import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'operator_model.dart';

class StaffRepository {
  final SupabaseClient _client;

  StaffRepository(this._client);

  Future<List<OperatorModel>> getOperators(String orgId) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('org_id', orgId)
        .eq('role', 'tom_operator')
        .eq('is_active', true)
        .order('full_name', ascending: true);

    final List<OperatorModel> operators = [];

    for (final row in response as List) {
      final weekOffData = await _client
          .from('attendance')
          .select('id')
          .eq('operator_id', row['id'])
          .eq('status', 'absent');

      final weekOffCount = (weekOffData as List).length;
      operators.add(
        OperatorModel.fromMap(
          row as Map<String, dynamic>,
          weekOffs: weekOffCount,
        ),
      );
    }

    return operators;
  }

  Future<void> addOperator({
    required String orgId,
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
  }) async {
    await _client.from('profiles').insert({
      'id': const Uuid().v4(),
      'org_id': orgId,
      'role': 'tom_operator',
      'full_name': fullName.trim(),
      'phone_number': phoneNumber.trim(),
      'biometric_id': biometricId?.trim(),
      'company_id': companyId?.trim(),
      'bmrcl_id': bmrclId?.trim(),
      'is_active': true,
    });
  }

  Future<void> updateOperator({
    required String operatorId,
    required String fullName,
    required String phoneNumber,
    String? biometricId,
    String? companyId,
    String? bmrclId,
  }) async {
    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          'phone_number': phoneNumber.trim(),
          'biometric_id': biometricId?.trim(),
          'company_id': companyId?.trim(),
          'bmrcl_id': bmrclId?.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', operatorId);
  }

  Future<void> deleteOperator(String operatorId) async {
    await _client.from('profiles').delete().eq('id', operatorId);
  }
}
