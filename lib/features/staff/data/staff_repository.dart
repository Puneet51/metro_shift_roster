import 'package:supabase_flutter/supabase_flutter.dart';
import 'operator_model.dart';

class StaffRepository {
  final SupabaseClient _client;

  StaffRepository(this._client);

  /// Fetches operators under the organization
  /// Fetches operators under the organization or specific supervisor
  Future<List<OperatorModel>> getOperators(
    String orgId, {
    String? supervisorId,
  }) async {
    try {
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
            father_name,
            doj,
            esi_no,
            is_active,
            has_pin,
            face_embedding,
            created_at,
            parent_supervisor_id
          ''')
          .eq('role', 'operator')
          .eq('is_active', true);

      // STRICT FILTER: If supervisorId is passed, ONLY fetch operators created by this specific supervisor
      if (supervisorId != null && supervisorId.isNotEmpty) {
        query = query
            .eq('parent_supervisor_id', supervisorId)
            .eq('org_id', orgId);
      } else if (orgId.isNotEmpty) {
        query = query.eq('org_id', orgId);
      } else {
        return [];
      }

      final response = await query.order('full_name', ascending: true);
      final operatorList = response as List;

      if (operatorList.isEmpty) {
        return [];
      }

      final operatorIds = operatorList
          .map((row) => row['id'].toString())
          .toList();

      final Map<String, int> weekOffMap = {};
      final Set<String> weekOffTodayIds = {};
      final now = DateTime.now();
      final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final monthStart = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final nextMonthDate = '${nextMonth.year.toString().padLeft(4, '0')}-${nextMonth.month.toString().padLeft(2, '0')}-01';

      // These two independent staffing lookups run in parallel so the staff
      // screen does not wait for them one after another.
      try {
        final results = await Future.wait<dynamic>([
          _client
              .from('attendance')
              .select('operator_id, duty_date, status')
              .inFilter('operator_id', operatorIds)
              .eq('status', 'week_off')
              .gte('duty_date', monthStart)
              .lt('duty_date', nextMonthDate),
          _client
              .from('shift_assignments')
              .select('operator_id, shifts!inner(duty_date, is_published)')
              .inFilter('operator_id', operatorIds)
              .eq('shifts.duty_date', today)
              .eq('shifts.is_published', true),
        ]);

        for (final raw in results[0] as List) {
          final att = Map<String, dynamic>.from(raw as Map);
          final opId = att['operator_id']?.toString() ?? '';
          if (opId.isEmpty) continue;
          weekOffMap[opId] = (weekOffMap[opId] ?? 0) + 1;
        }

        final assignedIds = <String>{};
        for (final raw in results[1] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['operator_id']?.toString() ?? '';
          if (id.isNotEmpty) assignedIds.add(id);
        }
        for (final id in operatorIds) {
          if (!assignedIds.contains(id)) weekOffTodayIds.add(id);
        }
      } catch (_) {
        // Keep the operator list available even if the optional staffing
        // metrics are temporarily unavailable.
      }

      return operatorList.map((row) {
        final id = row['id'].toString();
        return OperatorModel.fromMap(
          row as Map<String, dynamic>,
          weekOffs: weekOffMap[id] ?? 0,
          isWeekOffToday: weekOffTodayIds.contains(id),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Adds an operator securely passing all statutory and identity parameters
  Future<void> addOperator({
    required String orgId,
    required String fullName,
    required String phoneNumber,
    required String supervisorId,
    String? biometricId,
    String? companyId,
    String? bmrclId,
    String? fatherName,
    String? empCode,
    String? esiNo,
    String? uanNo,
    String? doj,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final res = await _client.rpc(
      'create_staff_operator',
      params: {
        'p_full_name': fullName.trim(),
        'p_phone_number': cleanPhone,
        'p_role': 'operator',
        'p_supervisor_id': supervisorId,
        if (orgId.isNotEmpty) 'p_org_id': orgId,
        'p_bmrcl_id': bmrclId?.trim().isNotEmpty == true
            ? bmrclId!.trim()
            : null,
        'p_company_id': companyId?.trim().isNotEmpty == true
            ? companyId!.trim()
            : null,
        'p_biometric_id': biometricId?.trim().isNotEmpty == true
            ? biometricId!.trim()
            : null,
        'p_father_name': fatherName?.trim().isNotEmpty == true
            ? fatherName!.trim()
            : null,
        'p_emp_code': empCode?.trim().isNotEmpty == true
            ? empCode!.trim()
            : null,
        'p_esi_no': esiNo?.trim().isNotEmpty == true ? esiNo!.trim() : null,
        'p_uan_no': uanNo?.trim().isNotEmpty == true ? uanNo!.trim() : null,
        'p_doj': (doj != null && doj.trim().isNotEmpty) ? doj.trim() : null,
      },
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to register operator');
    }
  }

  /// Updates an operator with complete muster roll and identity details
  Future<void> updateOperator({
    required String operatorId,
    required String supervisorId,
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
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
    final cleanDoj = (doj != null && doj.trim().isNotEmpty) ? doj.trim() : null;

    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          'phone_number': cleanPhone,
          'biometric_id': biometricId?.trim().isNotEmpty == true
              ? biometricId!.trim()
              : null,
          'company_id': companyId?.trim().isNotEmpty == true
              ? companyId!.trim()
              : null,
          'bmrcl_id': bmrclId?.trim().isNotEmpty == true
              ? bmrclId!.trim()
              : null,
          'emp_code': empCode?.trim().isNotEmpty == true
              ? empCode!.trim()
              : null,
          'father_name': fatherName?.trim().isNotEmpty == true
              ? fatherName!.trim()
              : null,
          'esi_no': esiNo?.trim().isNotEmpty == true ? esiNo!.trim() : null,
          'uan_no': uanNo?.trim().isNotEmpty == true ? uanNo!.trim() : null,
          'doj': cleanDoj,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', operatorId)
        .eq('parent_supervisor_id', supervisorId);
  }

  /// Deactivates an operator
  Future<void> deleteOperator({
    required String operatorId,
    required String supervisorId,
  }) async {
    await _client
        .from('profiles')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', operatorId)
        .eq('parent_supervisor_id', supervisorId);
  }
}
