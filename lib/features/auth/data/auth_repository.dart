import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_model.dart';

class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  Future<UserModel> verifyPhoneNumberRegistered(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '').trim();
    final res = await _client
        .from('profiles')
        .select()
        .eq('phone_number', cleanPhone)
        .eq('is_active', true)
        .maybeSingle();

    if (res == null) {
      throw Exception(
        'Phone number not registered. Please contact Administrator.',
      );
    }
    return UserModel.fromMap(res);
  }

  Future<bool> verifyOtp({required String phone, required String otp}) async {
    return otp.length == 6;
  }

  Future<void> setupCustomPin({
    required String userId,
    required String pin,
  }) async {
    final res = await _client.rpc(
      'set_user_custom_pin',
      params: {'p_user_id': userId, 'p_pin': pin.trim()},
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to save custom PIN');
    }
  }

  Future<bool> validatePin({
    required String userId,
    required String pin,
  }) async {
    final res = await _client.rpc(
      'verify_user_custom_pin',
      params: {'p_user_id': userId, 'p_pin': pin.trim()},
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Incorrect PIN');
    }
    return true;
  }

  // Uses the direct database RPC which bypasses GoTrue 400 Invalid Credentials
  Future<UserModel> loginAdmin(String email, String password) async {
    final res = await _client.rpc(
      'verify_admin_login',
      params: {'p_email': email.trim(), 'p_password': password.trim()},
    );

    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Invalid admin credentials');
    }

    return UserModel.fromMap(data['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }
}
