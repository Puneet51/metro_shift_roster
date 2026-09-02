import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/auth/presentation/auth_provider.dart';
import 'features/auth/presentation/phone_login_screen.dart';
import 'features/dashboard/presentation/operator_home_screen.dart';
import 'features/dashboard/presentation/supervisor_home_screen.dart';
import 'features/admin/presentation/admin_dashboard_screen.dart';

class NammaMetroApp extends ConsumerWidget {
  const NammaMetroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return MaterialApp(
      title: 'Metro Shift Roster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          primary: const Color(0xFF1E3A8A),
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
      ),
      home: _resolveRootScreen(authState),
    );
  }

  Widget _resolveRootScreen(AuthState state) {
    if (state.status == AuthStatus.authenticated && state.user != null) {
      switch (state.user!.role) {
        case 'admin':
          return const AdminDashboardScreen();
        case 'supervisor':
          return const SupervisorHomeScreen();
        case 'tom_operator':
          return const OperatorHomeScreen();
      }
    }
    return const PhoneLoginScreen();
  }
}
