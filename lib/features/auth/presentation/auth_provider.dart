import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/core/services/push_notification_service.dart';
import '../data/auth_repository.dart';
import '../data/user_model.dart';

enum AuthStatus {
  initial,
  authenticating,
  needsOtpAndPinSetup,
  pinRequired,
  authenticated,
  unauthenticated,
  error,
}

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? pendingPhone;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.pendingPhone,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? pendingPhone,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      pendingPhone: pendingPhone ?? this.pendingPhone,
      errorMessage: errorMessage,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(SupabaseService.client);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  static const _userSessionKey = 'metro_cached_user_session';

  AuthNotifier(this._repo) : super(const AuthState()) {
    restoreSession();
  }

  // Restore stored session on app startup
  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userSessionKey);

      if (userJson != null) {
        final Map<String, dynamic> userMap = jsonDecode(userJson);
        final user = UserModel.fromMap(userMap);

        // Bypass backend deactivation and DB profile checks for Admin on Web
        if (user.role == 'admin') {
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
          return;
        }

        // Verify active status in real-time for regular operators / supervisors
        final profile = await SupabaseService.client
            .from('profiles')
            .select('is_active')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null && profile['is_active'] == false) {
          await logout();
          state = const AuthState(
            status: AuthStatus.unauthenticated,
            errorMessage: 'Your account has been deactivated by administrator.',
          );
          return;
        }

        state = state.copyWith(status: AuthStatus.authenticated, user: user);

        if (!kIsWeb) {
          await PushNotificationService.syncFCMToken(user.id);
        }
        return;
      }

      state = state.copyWith(status: AuthStatus.unauthenticated);
    } catch (e) {
      debugPrint('Error restoring session: $e');
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _cacheUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionKey, jsonEncode(user.toMap()));
  }

  void setUser(UserModel user) {
    _cacheUser(user);
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
    if (!kIsWeb) {
      PushNotificationService.syncFCMToken(user.id);
    }
  }

  void resetToPhoneInput() {
    state = const AuthState(status: AuthStatus.initial);
  }

  Future<void> checkPhone(String phone) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      final user = await _repo.verifyPhoneNumberRegistered(phone);

      // Check if user is active
      final profile = await SupabaseService.client
          .from('profiles')
          .select('is_active')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null && profile['is_active'] == false) {
        throw Exception('Your account is deactivated. Contact Administrator.');
      }

      if (user.hasPinConfigured) {
        state = state.copyWith(
          status: AuthStatus.pinRequired,
          user: user,
          pendingPhone: phone,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.needsOtpAndPinSetup,
          user: user,
          pendingPhone: phone,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> verifyOtpAndSetCustomPin({
    required String otp,
    required String newPin,
    required String confirmPin,
  }) async {
    if (newPin != confirmPin) {
      state = state.copyWith(
        status: state.status,
        errorMessage: 'PINs do not match. Please re-enter.',
      );
      return;
    }

    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      if (state.pendingPhone == null || state.user == null) {
        throw Exception('Session expired. Please re-enter your phone number.');
      }

      // Check active status
      final profile = await SupabaseService.client
          .from('profiles')
          .select('is_active')
          .eq('id', state.user!.id)
          .maybeSingle();

      if (profile != null && profile['is_active'] == false) {
        throw Exception('Your account is deactivated. Contact Administrator.');
      }

      // Test OTP acceptance: accept valid 6-digit code
      if (otp.trim().length != 6) {
        throw Exception('Invalid 6-digit verification code.');
      }

      await _repo.setupCustomPin(userId: state.user!.id, pin: newPin);

      final updatedUser = state.user!.copyWith(hasPinConfigured: true);
      await _cacheUser(updatedUser);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: updatedUser,
      );

      if (!kIsWeb) {
        await PushNotificationService.syncFCMToken(updatedUser.id);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> loginWithPin(String pin) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      if (state.user == null) throw Exception('No active session.');

      // Check if user is active
      final profile = await SupabaseService.client
          .from('profiles')
          .select('is_active')
          .eq('id', state.user!.id)
          .maybeSingle();

      if (profile != null && profile['is_active'] == false) {
        throw Exception('Your account is deactivated. Contact Administrator.');
      }

      await _repo.validatePin(userId: state.user!.id, pin: pin);

      await _cacheUser(state.user!);
      state = state.copyWith(status: AuthStatus.authenticated);

      if (!kIsWeb) {
        await PushNotificationService.syncFCMToken(state.user!.id);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.pinRequired,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> loginAdmin(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      final user = await _repo.loginAdmin(email, password);

      // Save session first so page refreshes persist
      await _cacheUser(user);

      // Transition immediately into authenticated state with the returned admin user
      state = AuthState(status: AuthStatus.authenticated, user: user);

      if (!kIsWeb) {
        await PushNotificationService.syncFCMToken(user.id);
      }
    } catch (e) {
      debugPrint('loginAdmin error: $e');
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userSessionKey);
    await _repo.signOut();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
