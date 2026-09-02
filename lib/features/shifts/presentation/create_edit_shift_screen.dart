import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';
import 'package:metro_shift_roster/features/staff/presentation/staff_provider.dart';
import 'shift_provider.dart';

class CreateEditShiftScreen extends ConsumerStatefulWidget {
  final String? initialStationId;
  const CreateEditShiftScreen({super.key, this.initialStationId});

  @override
  ConsumerState<CreateEditShiftScreen> createState() =>
      _CreateEditShiftScreenState();
}

class _CreateEditShiftScreenState extends ConsumerState<CreateEditShiftScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedStationId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoadingExisting = false;

  // [dateString] -> [stationId] -> [shiftName] -> [operatingSystemId] -> {operator_id, is_ot}
  final Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>>
  _dateRosterTree = {};

  // Persistent fallback template: [stationId] -> [shiftName] -> [operatingSystemId] -> {operator_id, is_ot}
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _mostRecentTemplate = {};

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.initialStationId;
    _loadExistingAssignments();
  }

  bool get _isPastDate {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return targetDate.isBefore(todayMidnight);
  }

  Future<void> _loadExistingAssignments() async {
    setState(() => _isLoadingExisting = true);
    try {
      final shifts = await ref.read(supervisorShiftsProvider.future);

      // Sort shifts ascending so the newest/most recent assignments persist to _mostRecentTemplate
      final sortedShifts = List.of(shifts)
        ..sort((a, b) => a.dutyDate.compareTo(b.dutyDate));

      for (final s in sortedShifts) {
        _dateRosterTree.putIfAbsent(s.dutyDate, () => {});
        _dateRosterTree[s.dutyDate]!.putIfAbsent(s.stationId, () => {});
        _dateRosterTree[s.dutyDate]![s.stationId]!.putIfAbsent(
          s.shiftName,
          () => {},
        );

        _mostRecentTemplate.putIfAbsent(s.stationId, () => {});
        _mostRecentTemplate[s.stationId]!.putIfAbsent(s.shiftName, () => {});

        for (final a in s.assignments) {
          if (a.operatorId.isNotEmpty) {
            final assignmentData = {
              'operator_id': a.operatorId,
              'is_ot': a.isOt,
            };

            _dateRosterTree[s.dutyDate]![s.stationId]![s.shiftName]![a
                .operatingSystemId] = Map.from(
              assignmentData,
            );

            // Keep the latest assigned operator and counter configuration
            _mostRecentTemplate[s.stationId]![s.shiftName]![a
                .operatingSystemId] = Map.from(
              assignmentData,
            );
          }
        }
      }

      // Pre-fill current selected station with recent template if present
      final stations = ref.read(stationsListProvider).value ?? [];
      if (_selectedStationId != null) {
        final matches = stations.where((s) => s.id == _selectedStationId);
        if (matches.isNotEmpty) {
          _initStationRoster(matches.first);
        }
      }
    } catch (e) {
      debugPrint('Error pre-loading shifts: $e');
    }
    setState(() => _isLoadingExisting = false);
  }

  void _initStationRoster(StationModel stn) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _dateRosterTree.putIfAbsent(dateKey, () => {});
    _dateRosterTree[dateKey]!.putIfAbsent(stn.id, () => {});

    for (final tmpl in stn.shiftTemplates) {
      _dateRosterTree[dateKey]![stn.id]!.putIfAbsent(tmpl.shiftName, () => {});

      for (final sys in stn.operatingSystems) {
        // Carry forward the most recent assigned operator if this date is empty
        final fallback = _mostRecentTemplate[stn.id]?[tmpl.shiftName]?[sys.id];

        _dateRosterTree[dateKey]![stn.id]![tmpl.shiftName]!.putIfAbsent(
          sys.id,
          () => {
            'operator_id': fallback?['operator_id'],
            'is_ot': fallback?['is_ot'] ?? false,
          },
        );
      }
    }
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });

    final stations = ref.read(stationsListProvider).value ?? [];
    if (_selectedStationId != null) {
      final matches = stations.where((s) => s.id == _selectedStationId);
      if (matches.isNotEmpty) {
        _initStationRoster(matches.first);
      }
    }
  }

  Future<void> _publishAllConfiguredRosters() async {
    if (_isPastDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completed and past duties are locked. You cannot edit or publish shifts for past dates.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final stations = ref.read(stationsListProvider).value ?? [];
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

    final targetStations = _selectedStationId != null
        ? stations.where((s) => s.id == _selectedStationId).toList()
        : stations;

    final dateRosters = _dateRosterTree[formattedDate];
    if (dateRosters == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please assign at least one staff member before publishing.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    bool hasPublishedAny = false;

    for (final stn in targetStations) {
      final stationRosters = dateRosters[stn.id];
      if (stationRosters == null) continue;

      for (final tmpl in stn.shiftTemplates) {
        final shiftAssignments = stationRosters[tmpl.shiftName];
        if (shiftAssignments == null) continue;

        final List<Map<String, dynamic>> rawAssignments = [];
        shiftAssignments.forEach((sysId, data) {
          final opId = data['operator_id'];
          if (opId != null && opId.toString().trim().isNotEmpty) {
            rawAssignments.add({
              'operating_system_id': sysId,
              'operator_id': opId,
              'is_ot': data['is_ot'] ?? false,
            });

            // Update persistent fallback template
            _mostRecentTemplate.putIfAbsent(stn.id, () => {});
            _mostRecentTemplate[stn.id]!.putIfAbsent(tmpl.shiftName, () => {});
            _mostRecentTemplate[stn.id]![tmpl.shiftName]![sysId] = {
              'operator_id': opId,
              'is_ot': data['is_ot'] ?? false,
            };
          }
        });

        if (rawAssignments.isNotEmpty) {
          await ref
              .read(shiftActionNotifierProvider.notifier)
              .publishShift(
                stationId: stn.id,
                shiftName: tmpl.shiftName,
                dutyDate: formattedDate,
                startTime: tmpl.startTime,
                endTime: tmpl.endTime,
                dailyAmount: stn.defaultFixedAmount,
                rawAssignments: rawAssignments,
              );
          hasPublishedAny = true;
        }
      }
    }

    if (!hasPublishedAny) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select at least one staff member before publishing.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    ref.invalidate(supervisorShiftsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift Roster Published Successfully!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.pop(context, formattedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(stationsListProvider);
    final staffAsync = ref.watch(staffListProvider);
    final actionState = ref.watch(shiftActionNotifierProvider);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        title: const Text(
          'Shift Roster Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingExisting
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.calendar_today_rounded,
                                  color: Color(0xFF1E3A8A),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Roster Duty Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    DateFormat(
                                      'EEEE, dd MMM yyyy',
                                    ).format(_selectedDate),
                                    style: TextStyle(
                                      color: _isPastDate
                                          ? Colors.red.shade700
                                          : Colors.grey.shade600,
                                      fontWeight: _isPastDate
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF1E3A8A)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 30),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 90),
                                ),
                              );
                              if (picked != null) {
                                _onDateChanged(picked);
                              }
                            },
                            child: const Text('Change Date'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_isPastDate)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This shift date has already passed. Existing records are locked and cannot be republished or altered.',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),

                    stationsAsync.when(
                      data: (stations) {
                        if (stations.isEmpty) {
                          return const Text(
                            'No stations registered. Please create a station first.',
                          );
                        }

                        StationModel? currentStation;
                        if (_selectedStationId != null) {
                          final matches = stations.where(
                            (s) => s.id == _selectedStationId,
                          );
                          if (matches.isNotEmpty) {
                            currentStation = matches.first;
                            _initStationRoster(currentStation);
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Select Station to Assign Duty',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                prefixIcon: Icon(
                                  Icons.subway_rounded,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              value: _selectedStationId,
                              items: stations
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  final stn = stations.firstWhere(
                                    (s) => s.id == id,
                                  );
                                  _initStationRoster(stn);
                                  setState(() => _selectedStationId = id);
                                }
                              },
                            ),
                            const SizedBox(height: 18),
                            if (currentStation != null) ...[
                              Row(
                                children: [
                                  const Icon(
                                    Icons.desktop_windows_outlined,
                                    color: Color(0xFF1E3A8A),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${currentStation.name} TOM Counters & Shift Plans',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              staffAsync.when(
                                data: (staffList) {
                                  return ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount:
                                        currentStation!.shiftTemplates.length,
                                    itemBuilder: (ctx, shiftIdx) {
                                      final tmpl = currentStation!
                                          .shiftTemplates[shiftIdx];
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    tmpl.shiftName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      color: Color(0xFF1E3A8A),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFEFF6FF,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${tmpl.startTime} - ${tmpl.endTime}',
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFF2563EB,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const Divider(
                                                height: 18,
                                                color: Color(0xFFF1F5F9),
                                              ),

                                              ...currentStation!.operatingSystems.map((
                                                sys,
                                              ) {
                                                final curData =
                                                    _dateRosterTree[dateKey]?[currentStation!
                                                        .id]?[tmpl
                                                        .shiftName]?[sys.id];
                                                final assignedOpId =
                                                    curData?['operator_id'];

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 85,
                                                        child: Text(
                                                          sys.systemName,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12.5,
                                                                color: Color(
                                                                  0xFF334155,
                                                                ),
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          isDense: true,
                                                          decoration: const InputDecoration(
                                                            contentPadding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 8,
                                                                ),
                                                            border:
                                                                OutlineInputBorder(),
                                                            fillColor: Color(
                                                              0xFFF8FAFC,
                                                            ),
                                                            filled: true,
                                                          ),
                                                          value: assignedOpId,
                                                          hint: const Text(
                                                            '-- Unassigned --',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          items: [
                                                            const DropdownMenuItem(
                                                              value: null,
                                                              child: Text(
                                                                '-- Unassigned --',
                                                                style:
                                                                    TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                              ),
                                                            ),
                                                            ...staffList.map(
                                                              (
                                                                s,
                                                              ) => DropdownMenuItem(
                                                                value: s.id,
                                                                child: Text(
                                                                  s.fullName,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            12.5,
                                                                      ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                          onChanged: _isPastDate
                                                              ? null
                                                              : (val) {
                                                                  setState(() {
                                                                    _dateRosterTree[dateKey]![currentStation!
                                                                            .id]![tmpl
                                                                            .shiftName]![sys
                                                                            .id]!['operator_id'] =
                                                                        val;
                                                                    // Update fallback template on manual change
                                                                    _mostRecentTemplate
                                                                        .putIfAbsent(
                                                                          currentStation!
                                                                              .id,
                                                                          () =>
                                                                              {},
                                                                        );
                                                                    _mostRecentTemplate[currentStation!
                                                                            .id]!
                                                                        .putIfAbsent(
                                                                          tmpl.shiftName,
                                                                          () =>
                                                                              {},
                                                                        );
                                                                    _mostRecentTemplate[currentStation!
                                                                        .id]![tmpl
                                                                        .shiftName]![sys
                                                                        .id] = {
                                                                      'operator_id':
                                                                          val,
                                                                      'is_ot':
                                                                          curData?['is_ot'] ??
                                                                          false,
                                                                    };
                                                                  });
                                                                },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        onTap: _isPastDate
                                                            ? null
                                                            : () {
                                                                setState(() {
                                                                  final cur =
                                                                      curData?['is_ot'] ??
                                                                      false;
                                                                  final updatedOt =
                                                                      !cur;
                                                                  _dateRosterTree[dateKey]![currentStation!
                                                                          .id]![tmpl
                                                                          .shiftName]![sys
                                                                          .id]!['is_ot'] =
                                                                      updatedOt;

                                                                  _mostRecentTemplate
                                                                      .putIfAbsent(
                                                                        currentStation!
                                                                            .id,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  _mostRecentTemplate[currentStation!
                                                                          .id]!
                                                                      .putIfAbsent(
                                                                        tmpl.shiftName,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  _mostRecentTemplate[currentStation!
                                                                      .id]![tmpl
                                                                      .shiftName]![sys
                                                                      .id] = {
                                                                    'operator_id':
                                                                        assignedOpId,
                                                                    'is_ot':
                                                                        updatedOt,
                                                                  };
                                                                });
                                                              },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 9,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                (curData?['is_ot'] ??
                                                                    false)
                                                                ? const Color(
                                                                    0xFF7C3AED,
                                                                  )
                                                                : const Color(
                                                                    0xFFF1F5F9,
                                                                  ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  (curData?['is_ot'] ??
                                                                      false)
                                                                  ? const Color(
                                                                      0xFF7C3AED,
                                                                    )
                                                                  : const Color(
                                                                      0xFFCBD5E1,
                                                                    ),
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'OT',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  (curData?['is_ot'] ??
                                                                      false)
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF64748B,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                loading: () => const CircularProgressIndicator(
                                  color: Color(0xFF1E3A8A),
                                ),
                                error: (e, _) => Text('Error: $e'),
                              ),
                            ],
                          ],
                        );
                      },
                      loading: () => const LinearProgressIndicator(
                        color: Color(0xFF1E3A8A),
                      ),
                      error: (e, _) => Text('Error: $e'),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPastDate
                            ? Colors.grey
                            : const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.send_rounded),
                      onPressed: (_isPastDate || actionState.isLoading)
                          ? null
                          : _publishAllConfiguredRosters,
                      label: actionState.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isPastDate
                                  ? 'Locked (Completed Duty)'
                                  : 'Publish Station Shift Roster',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
