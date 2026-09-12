import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/core/services/push_notification_service.dart';
import '../data/auth_repository.dart';
import '../data/user_model.dart';

enum AuthStatus {
  initial,
  authenticating,
  needsPinSetup,
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

  StreamSubscription<supabase.AuthState>? _authStateSubscription;

  AuthNotifier(this._repo) : super(const AuthState()) {
    _listenToSupabaseAuth();
    restoreSession();
  }

  void _listenToSupabaseAuth() {
    _authStateSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == supabase.AuthChangeEvent.signedOut) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userSessionKey);
        if (mounted) {
          state = const AuthState(status: AuthStatus.unauthenticated);
        }
      } else if (event == supabase.AuthChangeEvent.tokenRefreshed) {
        // Keep the cached profile in sync with the live Supabase session.
        if (mounted && state.user != null && state.status == AuthStatus.unauthenticated) {
          state = state.copyWith(status: AuthStatus.authenticated);
        }
      }
    });
  }

  // Restore stored session on app startup
  Future<void> restoreSession() async {
    try {
      final session = SupabaseService.client.auth.currentSession;
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userSessionKey);

      if (userJson != null) {
        // A cached profile is not enough to authorize Supabase REST/RPC calls.
        // If the native Supabase session is gone (for example after an invalid
        // refresh token), never keep the UI in a fake authenticated state.
        if (session == null) {
          await prefs.remove(_userSessionKey);
          state = const AuthState(status: AuthStatus.unauthenticated);
          return;
        }

        Map<String, dynamic> userMap = jsonDecode(userJson);
        UserModel user = UserModel.fromMap(userMap);

        // Check if token has expired and refresh if necessary.
        if (session.isExpired) {
          try {
            final refreshed =
                await SupabaseService.client.auth.refreshSession();
            if (refreshed.session == null) {
              await prefs.remove(_userSessionKey);
              state = const AuthState(status: AuthStatus.unauthenticated);
              return;
            }
          } catch (_) {
            await prefs.remove(_userSessionKey);
            state = const AuthState(status: AuthStatus.unauthenticated);
            return;
          }
        }

        // Verify active status in real-time
        final profile = await SupabaseService.client
            .from('profiles')
            .select('is_active, has_pin')
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

        final bool hasPin = profile?['has_pin'] ?? user.hasPinConfigured;
        final updatedUser = user.copyWith(hasPinConfigured: hasPin);

        // First-login Security PIN setup applies to every non-admin staff
        // account: primary supervisors, relievers, and operators.
        if (!hasPin && user.role != 'admin') {
          state = state.copyWith(
            status: AuthStatus.needsPinSetup,
            user: updatedUser,
            pendingPhone: updatedUser.phoneNumber,
          );
          return;
        }

        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: updatedUser,
        );

        if (!kIsWeb) {
          await PushNotificationService.syncFCMToken(user.id);
        }
        return;
      }

      state = state.copyWith(status: AuthStatus.unauthenticated);
    } catch (e) {
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

  /// Check phone registration and prompt for PIN
  Future<void> checkPhone(String phone) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'\D'), '').trim();
      if (cleanPhone.length < 10) {
        throw Exception('Please enter a valid 10-digit mobile number');
      }

      final res = await SupabaseService.client.rpc(
        'check_phone_registration',
        params: {'p_phone': cleanPhone},
      );

      final data = res as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Phone verification failed');
      }

      final userMap = data['user'] as Map<String, dynamic>;
      final user = UserModel.fromMap(userMap);
      final bool hasConfiguredPin = userMap['has_pin'] == true;

      if (hasConfiguredPin) {
        state = state.copyWith(
          status: AuthStatus.pinRequired,
          user: user,
          pendingPhone: cleanPhone,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.needsPinSetup,
          user: user,
          pendingPhone: cleanPhone,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Authenticate with PIN and issue a native Supabase JWT Session
  /// Login using Phone & PIN via Edge Function
  Future<void> loginWithPin(String pin) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      final phone = state.pendingPhone ?? state.user?.phoneNumber;
      if (phone == null || phone.isEmpty) {
        throw Exception('Phone number missing. Please re-enter.');
      }

      // Calls repository -> Edge Function 'verify-pin' -> setSession()
      final authenticatedUser = await _repo.signInWithPhoneAndPin(
        phone: phone,
        pin: pin,
      );

      await _cacheUser(authenticatedUser);

      // First-login Security PIN setup applies to every non-admin staff
      // account: primary supervisors, relievers, and operators.
      if (!authenticatedUser.hasPinConfigured &&
          authenticatedUser.role != 'admin') {
        state = state.copyWith(
          status: AuthStatus.needsPinSetup,
          user: authenticatedUser,
          pendingPhone: phone,
        );
        return;
      }

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: authenticatedUser,
      );

      if (!kIsWeb) {
        await PushNotificationService.syncFCMToken(authenticatedUser.id);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.pinRequired,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// First-login / custom 4-digit Security PIN Setup for staff
  Future<void> setCustomPin({
    required String newPin,
    required String confirmPin,
  }) async {
    final cleanNewPin = newPin.trim();
    final cleanConfirmPin = confirmPin.trim();

    if (cleanNewPin != cleanConfirmPin) {
      state = state.copyWith(
        status: state.status,
        errorMessage: 'PINs do not match. Please re-enter.',
      );
      return;
    }

    if (cleanNewPin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(cleanNewPin)) {
      state = state.copyWith(
        status: state.status,
        errorMessage: 'PIN must be exactly 4 digits.',
      );
      return;
    }

    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );

    try {
      if (state.user == null) {
        throw Exception('Session expired. Please log in again.');
      }

      final targetUser = state.user!;
      final phone = state.pendingPhone ?? targetUser.phoneNumber;

      // Save the permanent application PIN. This PIN is NOT used as a
      // Supabase Auth password.
      await _repo.setupCustomPin(userId: targetUser.id, pin: cleanNewPin);

      // Now establish the real Supabase Auth session through the existing
      // phone + PIN authentication path. The verify-pin Edge Function
      // provisions/updates the internal Auth credentials and then the
      // client signs in normally.
      final authenticatedUser = await _repo.signInWithPhoneAndPin(
        phone: phone,
        pin: cleanNewPin,
      );

      final updatedUser = authenticatedUser.copyWith(hasPinConfigured: true);
      await _cacheUser(updatedUser);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: updatedUser,
        pendingPhone: phone,
        errorMessage: null,
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

  /// Supervisor resets an operator PIN
  Future<String> supervisorResetOperatorPin(String operatorPhone) async {
    if (state.user == null || state.user!.role != 'supervisor') {
      throw Exception('Unauthorized action.');
    }

    final tempPin = await _repo.supervisorGenerateAndSendPin(
      operatorPhone: operatorPhone,
      supervisorId: state.user!.id,
    );

    return tempPin;
  }

  Future<void> loginAdmin(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      errorMessage: null,
    );
    try {
      final user = await _repo.loginAdmin(email, password);
      await _cacheUser(user);
      state = AuthState(status: AuthStatus.authenticated, user: user);

      if (!kIsWeb) {
        await PushNotificationService.syncFCMToken(user.id);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userSessionKey);
    try {
      await SupabaseService.client.auth.signOut(scope: supabase.SignOutScope.local);
    } catch (_) {}
    try {
      await _repo.signOut();
    } catch (_) {}
    if (mounted) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
