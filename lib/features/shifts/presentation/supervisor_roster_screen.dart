import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'shift_provider.dart';
import 'create_edit_shift_screen.dart';
import '../data/shift_model.dart';

class SupervisorRosterScreen extends ConsumerStatefulWidget {
  final bool isReadOnly;
  const SupervisorRosterScreen({super.key, this.isReadOnly = false});

  @override
  ConsumerState<SupervisorRosterScreen> createState() =>
      _SupervisorRosterScreenState();
}

class _SupervisorRosterScreenState
    extends ConsumerState<SupervisorRosterScreen> {
  String? _selectedDutyDate;

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

  // Returns true if shift date is before today (Past Date Rule)
  bool _isPastDate(String dutyDateStr) {
    try {
      final dutyDate = DateTime.parse(dutyDateStr);
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final shiftDay = DateTime(dutyDate.year, dutyDate.month, dutyDate.day);
      return shiftDay.isBefore(todayMidnight);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openPublishScreen([String? stationId]) async {
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditShiftScreen(initialStationId: stationId),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedDutyDate = result;
      });
      ref.invalidate(supervisorShiftsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftsAsync = ref.watch(supervisorShiftsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        color: const Color(0xFF1E3A8A),
        onRefresh: () async => ref.invalidate(supervisorShiftsProvider),
        child: shiftsAsync.when(
          data: (allShifts) {
            // STRICT RULE: Filter out past dates so only Today & Upcoming shifts show in Roster
            final activeShifts = allShifts
                .where((s) => !_isPastDate(s.dutyDate))
                .toList();

            if (activeShifts.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 180),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            size: 48,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No Active or Upcoming Shifts',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completed shifts have moved to History.\nPublish new shifts for upcoming dates.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Ascending order: Today first, then upcoming dates
            final List<String> availableDates =
                activeShifts.map((s) => s.dutyDate).toSet().toList()
                  ..sort((a, b) => a.compareTo(b));

            if (_selectedDutyDate == null ||
                !availableDates.contains(_selectedDutyDate)) {
              _selectedDutyDate = availableDates.first;
            }

            final dateShifts = activeShifts
                .where((s) => s.dutyDate == _selectedDutyDate)
                .toList();

            final Map<String, List<ShiftModel>> groupedByStation = {};
            for (final shift in dateShifts) {
              groupedByStation
                  .putIfAbsent(shift.stationId, () => [])
                  .add(shift);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Filter Strip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: availableDates.map((dateStr) {
                        final isSelected = dateStr == _selectedDutyDate;
                        DateTime parsedDate;
                        try {
                          parsedDate = DateTime.parse(dateStr);
                        } catch (_) {
                          parsedDate = DateTime.now();
                        }

                        final now = DateTime.now();
                        final isToday =
                            parsedDate.year == now.year &&
                            parsedDate.month == now.month &&
                            parsedDate.day == now.day;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () =>
                                setState(() => _selectedDutyDate = dateStr),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF1E3A8A)
                                    : (isToday
                                          ? const Color(0xFFEFF6FF)
                                          : Colors.white),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF1E3A8A)
                                      : (isToday
                                            ? const Color(0xFF3B82F6)
                                            : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isToday
                                        ? Icons.timer_outlined
                                        : Icons.calendar_today_rounded,
                                    size: 13,
                                    color: isSelected
                                        ? Colors.white
                                        : (isToday
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF475569)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isToday
                                        ? 'Today (${DateFormat('dd MMM').format(parsedDate)})'
                                        : DateFormat(
                                            'EEE, dd MMM',
                                          ).format(parsedDate),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : (isToday
                                                ? const Color(0xFF1E3A8A)
                                                : const Color(0xFF334155)),
                                      fontWeight: isSelected || isToday
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Station Cards
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: groupedByStation.keys.length,
                    itemBuilder: (context, idx) {
                      final stationId = groupedByStation.keys.elementAt(idx);
                      final stationShifts = groupedByStation[stationId]!;
                      final stationName = stationShifts.first.stationName;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.subway_rounded,
                                          color: Color(0xFF1E3A8A),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        stationName,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!widget.isReadOnly)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Color(0xFF2563EB),
                                        size: 20,
                                      ),
                                      tooltip: 'Edit Station Shifts',
                                      onPressed: () =>
                                          _openPublishScreen(stationId),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              ...stationShifts.map((shift) {
                                final badgeColor = _getShiftBadgeColor(
                                  shift.shiftName,
                                );

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: true,
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                      leading: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          shift.shiftName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          const Icon(
                                            Icons.access_time_rounded,
                                            size: 14,
                                            color: Color(0xFF64748B),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            '${shift.startTime} - ${shift.endTime}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: !widget.isReadOnly
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text(
                                                      'Delete Shift',
                                                    ),
                                                    content: Text(
                                                      'Delete ${shift.shiftName} for $stationName?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Delete',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  await ref
                                                      .read(
                                                        shiftRepositoryProvider,
                                                      )
                                                      .deleteShift(shift.id);
                                                  ref.invalidate(
                                                    supervisorShiftsProvider,
                                                  );
                                                }
                                              },
                                            )
                                          : null,
                                      children: shift.assignments.isEmpty
                                          ? [
                                              const Padding(
                                                padding: EdgeInsets.all(12.0),
                                                child: Text(
                                                  'No operators assigned to this shift.',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ),
                                            ]
                                          : shift.assignments.map((a) {
                                              return Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 3,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE2E8F0,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .desktop_windows_outlined,
                                                      color: Color(0xFF64748B),
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '${a.systemName}: ${a.operatorName}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13,
                                                          color: Color(
                                                            0xFF1E293B,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (a.isOt)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFF7C3AED,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'OT',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
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
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
          ),
          error: (e, _) => Center(child: Text('Error loading shifts: $e')),
        ),
      ),
      floatingActionButton: widget.isReadOnly
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              elevation: 3,
              onPressed: () => _openPublishScreen(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Publish Shift',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
    );
  }
}
