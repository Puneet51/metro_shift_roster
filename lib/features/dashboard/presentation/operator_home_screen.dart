import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/utils/display_formatters.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/profile/presentation/profile_screen.dart';
import 'package:metro_shift_roster/features/shifts/presentation/supervisor_roster_screen.dart';
import 'package:metro_shift_roster/features/shifts/presentation/shift_provider.dart';
import 'package:metro_shift_roster/features/attendance/presentation/attendance_provider.dart';
import 'package:metro_shift_roster/features/notifications/presentation/notification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final operatorOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return {};

  final shifts = await ref.watch(operatorShiftsProvider.future);
  final today = DateTime.now();
  final todayKey =
      '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toDuty(shift, assignment) => {
        'duty_date': shift.dutyDate,
        'shift_name': shift.shiftName,
        'start_time': shift.startTime,
        'end_time': shift.endTime,
        'station_name': shift.stationName,
        'system_name': assignment.systemName,
        'operator_name': user.fullName,
        'is_ot': assignment.isOt,
      };

  final duties = <Map<String, dynamic>>[];
  for (final shift in shifts) {
    for (final assignment in shift.assignments) {
      duties.add(toDuty(shift, assignment));
    }
  }

  final todayDuties = duties.where((d) => d['duty_date'] == todayKey).toList();
  final upcoming = duties
      .where((d) =>
          d['duty_date'] != null &&
          d['duty_date'].toString().compareTo(todayKey) > 0)
      .toList()
    ..sort((a, b) {
      final d = a['duty_date'].toString().compareTo(b['duty_date'].toString());
      if (d != 0) return d;
      final t = a['start_time'].toString().compareTo(b['start_time'].toString());
      return t != 0 ? t : a['shift_name'].toString().compareTo(b['shift_name'].toString());
    });

  return {
    'today_duties': todayDuties,
    'upcoming_duties': upcoming,
  };
});

class OperatorHomeScreen extends ConsumerStatefulWidget {
  const OperatorHomeScreen({super.key});

  @override
  ConsumerState<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends ConsumerState<OperatorHomeScreen> {
  int _currentIndex = 0;
  RealtimeChannel? _realtimeChannel;
  Timer? _metricsRefreshTimer;

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
    _metricsRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      ref.invalidate(operatorShiftsProvider);
      ref.invalidate(operatorOverviewProvider);
      ref.invalidate(operatorSummaryMetricsProvider);
    });
  }

  void _setupRealtimeSubscription() {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;

    _realtimeChannel = SupabaseService.client
        .channel('public:operator_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'operator_id',
            value: user.id,
          ),
          callback: (_) {
            ref.invalidate(operatorOverviewProvider);
            ref.invalidate(operatorAttendanceProvider);
            ref.invalidate(operatorSummaryMetricsProvider);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shift_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'operator_id',
            value: user.id,
          ),
          callback: (_) {
            ref.invalidate(operatorShiftsProvider);
            ref.invalidate(operatorOverviewProvider);
            ref.invalidate(supervisorShiftsProvider);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'supervisor_id',
            value: user.effectiveSupervisorId,
          ),
          callback: (_) {
            ref.invalidate(operatorShiftsProvider);
            ref.invalidate(operatorOverviewProvider);
            ref.invalidate(supervisorShiftsProvider);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _metricsRefreshTimer?.cancel();
    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  Widget _buildShiftCard(Map<String, dynamic> duty, {bool showDate = false}) {
    final isOt = duty['is_ot'] == true;
    final baseTom =
        (duty['system_name'] != null &&
            duty['system_name'].toString().trim().isNotEmpty)
        ? duty['system_name'].toString().trim()
        : 'TOM 01';

    final operatorName =
        (duty['operator_name'] != null &&
            duty['operator_name'].toString().trim().isNotEmpty)
        ? duty['operator_name'].toString().trim()
        : (ref.watch(authNotifierProvider).user?.fullName ?? '');

    final counterDisplay = operatorName.isNotEmpty
        ? '$baseTom: $operatorName'
        : baseTom;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOt ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
          width: isOt ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.subway_rounded,
                        color: Color(0xFF1E3A8A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      duty['station_name'] ?? 'Station',
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (isOt)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'OT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        duty['shift_name'] ?? 'Shift',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                if (showDate && duty['duty_date'] != null) ...[
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    formatDisplayDate(duty['duty_date']?.toString()),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                const Icon(
                  Icons.access_time_rounded,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatDisplayTime(duty['start_time']?.toString())} - ${formatDisplayTime(duty['end_time']?.toString())}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.desktop_windows_outlined,
                    size: 16,
                    color: Color(0xFF1E3A8A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      counterDisplay,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(Map<String, dynamic> data) {
    final user = ref.watch(authNotifierProvider).user;
    final metrics = ref.watch(operatorSummaryMetricsProvider).value;

    final todayDuties = List<Map<String, dynamic>>.from(
      (data['today_duties'] as List<dynamic>?) ?? [],
    );
    final upcoming = List<Map<String, dynamic>>.from(
      (data['upcoming_duties'] as List<dynamic>?) ?? [],
    );

    int compareDuties(Map<String, dynamic> a, Map<String, dynamic> b) {
      final timeA = a['start_time']?.toString() ?? '';
      final timeB = b['start_time']?.toString() ?? '';
      final timeComp = timeA.compareTo(timeB);
      if (timeComp != 0) return timeComp;

      final shiftA = a['shift_name']?.toString() ?? '';
      final shiftB = b['shift_name']?.toString() ?? '';
      final shiftComp = shiftA.compareTo(shiftB);
      if (shiftComp != 0) return shiftComp;

      final tomA = a['system_name']?.toString() ?? '';
      final tomB = b['system_name']?.toString() ?? '';
      return tomA.compareTo(tomB);
    }

    todayDuties.sort(compareDuties);
    upcoming.sort((a, b) {
      final dateA = a['duty_date']?.toString() ?? '';
      final dateB = b['duty_date']?.toString() ?? '';
      final dateComp = dateA.compareTo(dateB);
      return dateComp != 0 ? dateComp : compareDuties(a, b);
    });

    return RefreshIndicator(
      color: const Color(0xFF1E3A8A),
      onRefresh: () async {
        ref.invalidate(operatorOverviewProvider);
        ref.invalidate(operatorAttendanceProvider);
        ref.invalidate(operatorSummaryMetricsProvider);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A8A).withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          user?.fullName ?? "Operator",
                          style: const TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'TOM Operator',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                _buildStatCard(
                  'Verified Duties',
                  '${metrics?.totalDuty ?? (data['total_duty'] ?? 0)}',
                  const Color(0xFF2563EB),
                  Icons.check_circle_rounded,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Credited Earnings',
                  '₹${(metrics?.earnings ?? (data['total_earnings'] ?? 0)).toInt()}',
                  const Color(0xFF059669),
                  Icons.currency_rupee_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildStatCard(
                  'Verified OT',
                  '${metrics?.otDutyCount ?? (data['total_ot'] ?? 0)}',
                  const Color(0xFF7C3AED),
                  Icons.more_time_rounded,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Week Offs',
                  '${metrics?.weekOffCount ?? (data['week_offs'] ?? 0)}',
                  const Color(0xFFD97706),
                  Icons.beach_access_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Today's Assigned Duties",
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (todayDuties.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${todayDuties.length} Duty Active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (todayDuties.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 36,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No specific roster assigned for today.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...todayDuties.map((duty) => _buildShiftCard(duty)),

            const SizedBox(height: 20),
            const Text(
              'Upcoming Shift Rosters',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),

            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No upcoming shifts scheduled.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...upcoming.map((duty) => _buildShiftCard(duty, showDate: true)),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(operatorOverviewProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 1,
        title: const Text(
          'Metro Shift Roster',
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
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile & Face ID',
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          overviewAsync.when(
            data: (data) => _buildDashboardTab(data),
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
          SupervisorRosterScreen(isReadOnly: true),
          SupervisorRosterScreen(isReadOnly: true, showHistory: true),
        ],
      ),
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
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          elevation: 0,
          onTap: (idx) => setState(() => _currentIndex = idx),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded),
              label: 'Roster',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
