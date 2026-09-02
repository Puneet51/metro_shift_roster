import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/reports/presentation/form_t_excel_generator.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';

class HistoryFilterState {
  final DateTime selectedMonth;
  final String selectedStationId;

  HistoryFilterState({
    required this.selectedMonth,
    this.selectedStationId = 'all',
  });

  HistoryFilterState copyWith({
    DateTime? selectedMonth,
    String? selectedStationId,
  }) {
    return HistoryFilterState(
      selectedMonth: selectedMonth ?? this.selectedMonth,
      selectedStationId: selectedStationId ?? this.selectedStationId,
    );
  }
}

final historyFilterProvider = StateProvider.autoDispose<HistoryFilterState>((
  ref,
) {
  final now = DateTime.now();
  return HistoryFilterState(
    selectedMonth: DateTime(now.year, now.month, 1),
    selectedStationId: 'all',
  );
});

// Fetches past published shifts along with assigned staff
final pastPublishedShiftsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null) return [];

      final filter = ref.watch(historyFilterProvider);
      final String orgId = user.orgId ?? '00000000-0000-0000-0000-000000000001';

      final startOfMonth = DateTime(
        filter.selectedMonth.year,
        filter.selectedMonth.month,
        1,
      );
      final nextMonth = DateTime(
        filter.selectedMonth.year,
        filter.selectedMonth.month + 1,
        1,
      );
      final endOfMonth = nextMonth.subtract(const Duration(days: 1));

      final startStr = DateFormat('yyyy-MM-dd').format(startOfMonth);
      final endStr = DateFormat('yyyy-MM-dd').format(endOfMonth);
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      var query = SupabaseService.client
          .from('shifts')
          .select('''
        id,
        duty_date,
        shift_name,
        start_time,
        end_time,
        daily_amount,
        stations!inner(id, name),
        shift_assignments(
          id,
          is_ot,
          profiles(id, full_name, emp_code),
          station_operating_systems(system_name)
        )
      ''')
          .eq('org_id', orgId)
          .gte('duty_date', startStr)
          .lte('duty_date', endStr)
          .lt('duty_date', nowStr); // Strictly past dates only

      if (filter.selectedStationId != 'all') {
        query = query.eq('station_id', filter.selectedStationId);
      }

      final res = await query.order('duty_date', ascending: false);
      return (res as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    });

class PunchHistoryScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  const PunchHistoryScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<PunchHistoryScreen> createState() => _PunchHistoryScreenState();
}

class _PunchHistoryScreenState extends ConsumerState<PunchHistoryScreen> {
  bool _isDownloading = false;

  Color _getShiftBadgeColor(String shiftName) {
    final lower = shiftName.toLowerCase();
    if (lower.contains('a') || lower.contains('morning')) {
      return const Color(0xFF2563EB);
    } else if (lower.contains('b') ||
        lower.contains('afternoon') ||
        lower.contains('evening')) {
      return const Color(0xFFD97706);
    } else if (lower.contains('c') || lower.contains('night')) {
      return const Color(0xFF7C3AED);
    }
    return const Color(0xFF0D9488);
  }

  Future<void> _exportExcel() async {
    final filter = ref.read(historyFilterProvider);
    final stations = ref.read(stationsListProvider).value ?? [];

    String stationName = 'All_Stations';
    if (filter.selectedStationId != 'all') {
      final matched = stations.where((s) => s.id == filter.selectedStationId);
      if (matched.isNotEmpty) {
        stationName = matched.first.name;
      }
    }

    setState(() => _isDownloading = true);
    try {
      await FormTExcelGenerator.generateAndDownloadExcel(
        stationId: filter.selectedStationId,
        stationName: stationName,
        selectedMonth: filter.selectedMonth,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Muster Roll for $stationName downloaded successfully!",
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showMonthPicker(BuildContext context, DateTime current) {
    showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime.now(),
      helpText: 'Select Month & Year',
    ).then((picked) {
      if (picked != null) {
        ref
            .read(historyFilterProvider.notifier)
            .update(
              (state) => state.copyWith(
                selectedMonth: DateTime(picked.year, picked.month, 1),
              ),
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final filter = ref.watch(historyFilterProvider);
    final stationsAsync = ref.watch(stationsListProvider);
    final pastShiftsAsync = ref.watch(pastPublishedShiftsProvider);
    final isSupervisor = user?.role == 'supervisor' || user?.role == 'admin';

    final content = RefreshIndicator(
      color: const Color(0xFF1E3A8A),
      onRefresh: () async => ref.invalidate(pastPublishedShiftsProvider),
      child: Column(
        children: [
          // Filter Toolbar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Month Picker
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () =>
                            _showMonthPicker(context, filter.selectedMonth),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                size: 16,
                                color: Color(0xFF1E3A8A),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  DateFormat(
                                    'MMM yyyy',
                                  ).format(filter.selectedMonth),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Station Dropdown
                    Expanded(
                      flex: 5,
                      child: stationsAsync.maybeWhen(
                        data: (stations) {
                          return DropdownButtonFormField<String>(
                            isDense: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                            ),
                            value: filter.selectedStationId,
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'All Stations',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
                              ...stations.map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    s.name,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                ref
                                    .read(historyFilterProvider.notifier)
                                    .update(
                                      (state) => state.copyWith(
                                        selectedStationId: val,
                                      ),
                                    );
                              }
                            },
                          );
                        },
                        orElse: () => const SizedBox(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    pastShiftsAsync.maybeWhen(
                      data: (shifts) => Text(
                        '${shifts.length} Past Roster Shifts',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      orElse: () => const SizedBox(),
                    ),
                    if (isSupervisor)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 16),
                        label: const Text(
                          'Download Attendance',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isDownloading ? null : _exportExcel,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Shift History Listing
          Expanded(
            child: pastShiftsAsync.when(
              data: (shifts) {
                if (shifts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No completed rosters for ${DateFormat('MMMM yyyy').format(filter.selectedMonth)}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: shifts.length,
                  itemBuilder: (ctx, i) {
                    final shift = shifts[i];
                    final stationData =
                        shift['stations'] as Map<String, dynamic>?;
                    final stationName = stationData?['name'] ?? 'Station';
                    final shiftName = shift['shift_name'] ?? 'Shift';
                    final dutyDate = shift['duty_date'] ?? '';
                    final badgeColor = _getShiftBadgeColor(shiftName);
                    final rawAssignments =
                        (shift['shift_assignments'] as List<dynamic>?) ?? [];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.015),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              shiftName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          title: Text(
                            '$stationName • $dutyDate',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            '${shift['start_time']} - ${shift['end_time']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          children: rawAssignments.isEmpty
                              ? [
                                  const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: Text(
                                      'No operators were assigned to this shift.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                ]
                              : rawAssignments.map((a) {
                                  final profile =
                                      a['profiles'] as Map<String, dynamic>?;
                                  final opName =
                                      profile?['full_name'] ?? 'Operator';
                                  final opId = profile?['id'];
                                  final system =
                                      a['station_operating_systems']
                                          as Map<String, dynamic>?;
                                  final sysName =
                                      system?['system_name'] ?? 'TOM Counter';
                                  final isOt = a['is_ot'] == true;
                                  final isCurrentUser = user?.id == opId;

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCurrentUser
                                          ? const Color(0xFFEFF6FF)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCurrentUser
                                            ? const Color(0xFF3B82F6)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.desktop_windows_outlined,
                                          color: isCurrentUser
                                              ? const Color(0xFF1E3A8A)
                                              : const Color(0xFF64748B),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$sysName: $opName',
                                            style: TextStyle(
                                              fontWeight: isCurrentUser
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              fontSize: 13,
                                              color: isCurrentUser
                                                  ? const Color(0xFF1E3A8A)
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                        if (isOt)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF7C3AED),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'OT',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
              ),
              error: (e, _) => Center(child: Text('Error loading history: $e')),
            ),
          ),
        ],
      ),
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E3A8A),
          title: const Text(
            'Completed Roster History',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: content,
      );
    }

    return Container(color: const Color(0xFFF8FAFC), child: content);
  }
}
