import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:metro_shift_roster/core/services/push_notification_service.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/auth/presentation/phone_login_screen.dart';
import 'package:metro_shift_roster/features/dashboard/presentation/operator_home_screen.dart';
import 'package:metro_shift_roster/features/dashboard/presentation/supervisor_home_screen.dart';
import 'package:metro_shift_roster/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:metro_shift_roster/features/auth/presentation/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load environment variables before initializing network services
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('DotEnv initialization error: $e');
  }

  // 2. Initialize Supabase
  await SupabaseService.initialize();

  // 3. Initialize Firebase & Push Notifications safely (Mobile only)
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      await PushNotificationService.initialize();
    } catch (e) {
      debugPrint('Firebase/Notification initialization error: $e');
    }
  }

  runApp(const ProviderScope(child: MetroShiftApp()));
}

class MetroShiftApp extends ConsumerStatefulWidget {
  const MetroShiftApp({super.key});

  @override
  ConsumerState<MetroShiftApp> createState() => _MetroShiftAppState();
}

class _MetroShiftAppState extends ConsumerState<MetroShiftApp> {
  bool _hasCheckedVersion = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return MaterialApp(
      title: 'Metro Shift Roster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        useMaterial3: true,
      ),
      home: !_hasCheckedVersion
          ? SplashScreen(
              onCheckComplete: () {
                setState(() {
                  _hasCheckedVersion = true;
                });
              },
            )
          : _resolveHomeScreen(authState),
    );
  }

  Widget _resolveHomeScreen(AuthState authState) {
    if (authState.status == AuthStatus.initial) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
        ),
      );
    }

    if (authState.status == AuthStatus.authenticated &&
        authState.user != null) {
      final role = authState.user!.role;
      if (role == 'admin') return const AdminDashboardScreen();
      if (role == 'supervisor') return const SupervisorHomeScreen();
      return const OperatorHomeScreen();
    }

    return const PhoneLoginScreen();
  }
}
