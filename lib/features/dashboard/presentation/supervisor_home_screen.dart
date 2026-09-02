import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/stations/presentation/stations_list_screen.dart';
import 'package:metro_shift_roster/features/staff/presentation/staff_list_screen.dart';
import 'package:metro_shift_roster/features/staff/presentation/week_off_leave_screen.dart';
import 'package:metro_shift_roster/features/shifts/presentation/supervisor_roster_screen.dart';
import 'package:metro_shift_roster/features/shifts/presentation/create_edit_shift_screen.dart';
import 'package:metro_shift_roster/features/punch_attendance/presentation/punch_audit_check_screen.dart';
import 'package:metro_shift_roster/features/punch_attendance/presentation/punch_history_screen.dart';
import 'package:metro_shift_roster/features/profile/presentation/profile_screen.dart';
import 'package:metro_shift_roster/features/notifications/presentation/notification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupervisorHomeScreen extends ConsumerStatefulWidget {
  const SupervisorHomeScreen({super.key});

  @override
  ConsumerState<SupervisorHomeScreen> createState() =>
      _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends ConsumerState<SupervisorHomeScreen> {
  int _currentIndex = 0;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = SupabaseService.client
        .channel('public:supervisor_roster_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shift_assignments',
          callback: (_) {
            if (mounted) setState(() {});
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          callback: (_) {
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      SupervisorRosterScreen(key: ValueKey('roster_tab_$_currentIndex')),
      const StationsListScreen(),
      const StaffListScreen(),
      const WeekOffLeaveScreen(),
      const PunchAuditCheckScreen(),
      const PunchHistoryScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 1,
        title: const Text(
          'Metro Shift Roster — Supervisor',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Publish Shift',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateEditShiftScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile & Biometrics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF1E3A8A),
          unselectedItemColor: const Color(0xFF94A3B8),
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          elevation: 0,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded),
              label: 'Roster',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.subway_outlined),
              activeIcon: Icon(Icons.subway_rounded),
              label: 'Stations',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_alt_rounded),
              label: 'Staff',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event_busy_outlined),
              activeIcon: Icon(Icons.event_busy_rounded),
              label: 'Week Off',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_front_outlined),
              activeIcon: Icon(Icons.camera_front_rounded),
              label: 'Punch',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              activeIcon: Icon(Icons.history_edu_rounded),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
