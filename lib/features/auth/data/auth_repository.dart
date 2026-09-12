import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_model.dart';

class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  SupabaseClient get client => _client;

  /// Legacy helper kept for compatibility with older callers.
  ///
  /// The current login flow no longer uses phone@phone.internal.
  /// The Edge Function now creates a unique internal email from the
  /// employee/profile UUID.
  String toShadowEmail(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '').trim();
    return '$cleanPhone@phone.internal';
  }

  /// 1. Verifies phone registration in profiles table.
  Future<UserModel> verifyPhoneNumberRegistered(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final res = await _client
        .from('profiles')
        .select()
        .eq('phone_number', cleanPhone)
        .eq('is_active', true)
        .maybeSingle();

    if (res == null) {
      throw Exception(
        'Phone number not registered. Please contact Administrator or Supervisor.',
      );
    }

    return UserModel.fromMap(res);
  }

  /// 2. Login using the application's Phone + custom PIN.
  ///
  /// Supabase Phone Authentication / SMS OTP is NOT used.
  ///
  /// Flow:
  ///   phone + PIN
  ///      -> verify-pin Edge Function
  ///      -> custom database PIN verification
  ///      -> internal Supabase email/password
  ///      -> normal GoTrue session
  Future<UserModel> signInWithPhoneAndPin({
    required String phone,
    required String pin,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '').trim();
    final cleanPin = pin.trim();

    if (cleanPhone.isEmpty) {
      throw Exception('Please enter your mobile number.');
    }

    if (cleanPin.isEmpty) {
      throw Exception('Please enter your Security PIN.');
    }

    try {
      final response = await _client.functions.invoke(
        'verify-pin',
        body: {'phone': cleanPhone, 'pin': cleanPin},
      );

      final data = response.data;

      Map<String, dynamic>? responseMap;
      if (data is Map) {
        responseMap = Map<String, dynamic>.from(data);
      }

      if (response.status != 200 || responseMap == null) {
        final errorMsg = responseMap?['error']?.toString();

        throw Exception(
          errorMsg ??
              'Incorrect PIN or unregistered account. Please check your credentials.',
        );
      }

      if (responseMap['success'] != true) {
        throw Exception(
          responseMap['error']?.toString() ??
              'Incorrect PIN or unregistered account.',
        );
      }

      final email = responseMap['email']?.toString();
      final password = responseMap['password']?.toString();
      final userId = responseMap['user_id']?.toString();

      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty ||
          userId == null ||
          userId.isEmpty) {
        throw Exception(
          'Authentication server returned incomplete login credentials.',
        );
      }

      /*
       * This is the normal Supabase Auth login.
       *
       * Phone Authentication is not involved here.
       * The email is an internal shadow identity created by verify-pin.
       */
      // A newly created Supabase Auth user can take a short moment to become
      // available to the password sign-in endpoint. Retry the same credentials
      // instead of making the user log out and sign in again manually.
      AuthResponse? authRes;
      AuthException? lastAuthError;

      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          authRes = await _client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          lastAuthError = null;
          break;
        } on AuthException catch (e) {
          lastAuthError = e;

          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      if (lastAuthError != null) {
        throw lastAuthError!;
      }

      if (authRes == null ||
          authRes!.session == null ||
          authRes!.user == null) {
        throw Exception('Failed to create the authentication session.');
      }

      // The Edge Function and Auth account use the same UUID as the
      // application profile for every staff member.
      if (authRes!.user!.id != userId) {
        await _client.auth.signOut();
        throw Exception(
          'Authentication account is not linked to this profile.',
        );
      }

      // Fetch the application profile using the verified profile/user ID.
      final profileRes = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromMap(profileRes);
    } on FunctionException catch (e) {
      String? msg;

      final details = e.details;
      if (details is Map) {
        msg = details['error']?.toString();
      } else if (details != null) {
        msg = details.toString();
      }

      throw Exception(
        msg ??
            'Unable to verify login. Please check your mobile number and PIN.',
      );
    } on AuthException catch (e) {
      throw Exception('Authentication failed. Please try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// 3. First-login / custom 4-digit Security PIN setup for staff.
  Future<void> setupCustomPin({
    required String userId,
    required String pin,
  }) async {
    try {
      final cleanPin = pin.trim();

      if (!RegExp(r'^\d{4}$').hasMatch(cleanPin)) {
        throw Exception('Security PIN must be exactly 4 digits.');
      }

      // The 4-digit application PIN is stored only in the custom PIN RPC.
      // Do NOT send it to Supabase Auth as a password: GoTrue requires
      // passwords to be at least 6 characters and this would produce a 422.

      final res = await _client.rpc(
        'set_user_custom_pin',
        params: {'p_user_id': userId, 'p_pin': cleanPin},
      );

      final data = Map<String, dynamic>.from(res as Map);

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to save custom PIN');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 4. Validates PIN against DB.
  Future<bool> validatePin({
    required String userId,
    required String pin,
  }) async {
    final res = await _client.rpc(
      'verify_user_custom_pin',
      params: {'p_user_id': userId, 'p_pin': pin.trim()},
    );

    final data = Map<String, dynamic>.from(res as Map);

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Incorrect PIN');
    }

    return true;
  }

  /// 5. Supervisor-Only PIN Reset.
  Future<String> supervisorGenerateAndSendPin({
    required String operatorPhone,
    required String supervisorId,
  }) async {
    final cleanPhone = operatorPhone.replaceAll(RegExp(r'\D'), '').trim();

    final operatorProfile = await _client
        .from('profiles')
        .select('id, full_name, parent_supervisor_id')
        .eq('phone_number', cleanPhone)
        .maybeSingle();

    if (operatorProfile == null) {
      throw Exception('No operator found with phone $cleanPhone');
    }

    final operatorId = operatorProfile['id'].toString();

    final rpcRes = await _client.rpc(
      'supervisor_reset_operator_pin',
      params: {'p_operator_id': operatorId, 'p_supervisor_id': supervisorId},
    );

    final result = Map<String, dynamic>.from(rpcRes as Map);

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to reset operator PIN');
    }

    final tempPin =
        result['temp_pin']?.toString() ??
        (1000 + Random.secure().nextInt(9000)).toString();

    return tempPin;
  }

  /// 6. Admin Login.
  Future<UserModel> loginAdmin(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    try {
      final authRes = await _client.auth.signInWithPassword(
        email: cleanEmail,
        password: cleanPassword,
      );

      final user = authRes.user;

      if (user == null) {
        throw Exception('Native admin authentication failed.');
      }

      var profileRes = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profileRes == null) {
        profileRes = await _client
            .from('profiles')
            .insert({
              'id': user.id,
              'full_name': 'Administrator',
              'role': 'admin',
              'is_active': true,
              'has_pin': true,
            })
            .select()
            .single();
      }

      return UserModel.fromMap(profileRes);
    } catch (e) {
      final res = await _client.rpc(
        'verify_admin_login',
        params: {'p_email': cleanEmail, 'p_password': cleanPassword},
      );

      final data = Map<String, dynamic>.from(res as Map);

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Invalid admin credentials');
      }

      return UserModel.fromMap(data['user'] as Map<String, dynamic>);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }
}
