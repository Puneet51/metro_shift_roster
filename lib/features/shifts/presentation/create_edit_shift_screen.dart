import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';
import 'package:metro_shift_roster/features/staff/presentation/staff_provider.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
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
  bool _publishAllStations = false;

  // [dateString] -> [stationId] -> [shiftName] -> [operatingSystemId] -> {operator_id, is_ot}
  final Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>>
  _dateRosterTree = {};

  // Latest known assignments per station: [stationId] -> [shiftName] -> [operatingSystemId] -> {operator_id, is_ot}
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _stationLatestTemplate = {};

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.initialStationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingAssignments();
    });
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

  bool get _isFutureDate {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return targetDate.isAfter(todayMidnight);
  }

  Future<void> _loadExistingAssignments() async {
    setState(() => _isLoadingExisting = true);
    try {
      final user = ref.read(authNotifierProvider).user;
      final orgId = user?.orgId ?? '';
      final supervisorId = user?.role == 'supervisor'
          ? (user?.id ?? '')
          : (user?.effectiveSupervisorId ?? '');

      // Load all shifts across all dates directly without date filter
      final shifts = await ref
          .read(shiftRepositoryProvider)
          .getSupervisorShifts(
            orgId,
            supervisorId: supervisorId,
            dutyDate: null,
          );

      final sortedShifts = List.of(shifts)
        ..sort((a, b) => a.dutyDate.compareTo(b.dutyDate));

      _dateRosterTree.clear();
      _stationLatestTemplate.clear();

      for (final s in sortedShifts) {
        _dateRosterTree.putIfAbsent(s.dutyDate, () => {});
        _dateRosterTree[s.dutyDate]!.putIfAbsent(s.stationId, () => {});
        _dateRosterTree[s.dutyDate]![s.stationId]!.putIfAbsent(
          s.shiftName,
          () => {},
        );

        _stationLatestTemplate.putIfAbsent(s.stationId, () => {});
        _stationLatestTemplate[s.stationId]!.putIfAbsent(s.shiftName, () => {});

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

            _stationLatestTemplate[s.stationId]![s.shiftName]![a
                .operatingSystemId] = Map.from(
              assignmentData,
            );
          }
        }
      }

      final stations = ref.read(stationsListProvider).value ?? [];
      for (final stn in stations) {
        _initStationRoster(stn);
      }

      if (_selectedStationId == null && stations.isNotEmpty) {
        _selectedStationId = stations.first.id;
      }
    } catch (e) {
      debugPrint('❌ Error loading shift assignments: $e');
    }
    if (mounted) {
      setState(() => _isLoadingExisting = false);
    }
  }

  List<StationShiftTemplate> _getShiftsForStation(StationModel stn) {
    if (stn.shiftTemplates.isNotEmpty) {
      return stn.shiftTemplates;
    }
    final suffix = stn.id.length >= 12
        ? stn.id.substring(stn.id.length - 12)
        : stn.id.padLeft(12, '0');
    return [
      StationShiftTemplate(
        id: '00000000-0000-0000-0001-$suffix',
        stationId: stn.id,
        shiftName: 'A Shift',
        startTime: '06:00:00',
        endTime: '14:00:00',
      ),
      StationShiftTemplate(
        id: '00000000-0000-0000-0002-$suffix',
        stationId: stn.id,
        shiftName: 'B Shift',
        startTime: '14:00:00',
        endTime: '22:00:00',
      ),
    ];
  }

  List<StationOperatingSystemModel> _getSystemsForStation(StationModel stn) {
    if (stn.operatingSystems.isNotEmpty) {
      return stn.operatingSystems;
    }
    final suffix = stn.id.length >= 12
        ? stn.id.substring(stn.id.length - 12)
        : stn.id.padLeft(12, '0');
    return [
      StationOperatingSystemModel(
        id: '00000000-0000-0000-0001-$suffix',
        stationId: stn.id,
        systemName: 'TOM 01',
      ),
      StationOperatingSystemModel(
        id: '00000000-0000-0000-0002-$suffix',
        stationId: stn.id,
        systemName: 'TOM 02',
      ),
    ];
  }

  void _initStationRoster(StationModel stn) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _dateRosterTree.putIfAbsent(dateKey, () => {});
    _dateRosterTree[dateKey]!.putIfAbsent(stn.id, () => {});

    final shifts = _getShiftsForStation(stn);
    final systems = _getSystemsForStation(stn);

    for (final tmpl in shifts) {
      _dateRosterTree[dateKey]![stn.id]!.putIfAbsent(tmpl.shiftName, () => {});

      for (int i = 0; i < systems.length; i++) {
        final sys = systems[i];
        final existing =
            _dateRosterTree[dateKey]![stn.id]![tmpl.shiftName]?[sys.id];

        if (existing == null) {
          var fallback =
              _stationLatestTemplate[stn.id]?[tmpl.shiftName]?[sys.id];

          if (fallback == null &&
              _stationLatestTemplate[stn.id]?[tmpl.shiftName] != null) {
            final latestMap = _stationLatestTemplate[stn.id]![tmpl.shiftName]!;
            if (i < latestMap.values.length) {
              fallback = latestMap.values.elementAt(i);
            }
          }

          _dateRosterTree[dateKey]![stn.id]![tmpl.shiftName]![sys.id] = {
            'operator_id': fallback?['operator_id'],
            'is_ot': fallback?['is_ot'] ?? false,
          };
        }
      }
    }
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });

    final stations = ref.read(stationsListProvider).value ?? [];
    for (final stn in stations) {
      _initStationRoster(stn);
    }
  }

  String? _getAssignedDutyLabel({
    required String operatorId,
    required String dateKey,
    required List<StationModel> allStations,
    required String currentStationId,
    required String currentShiftName,
    required String currentSysId,
  }) {
    final dayRosters = _dateRosterTree[dateKey];
    if (dayRosters == null) return null;

    for (final stnEntry in dayRosters.entries) {
      final stnId = stnEntry.key;
      final shiftsMap = stnEntry.value;

      final stnMatch = allStations.where((s) => s.id == stnId);
      final stnName = stnMatch.isNotEmpty ? stnMatch.first.name : 'Station';

      for (final shiftEntry in shiftsMap.entries) {
        final shiftName = shiftEntry.key;
        final countersMap = shiftEntry.value;

        for (final counterEntry in countersMap.entries) {
          final sysId = counterEntry.key;
          final opId = counterEntry.value['operator_id'];

          if (stnId == currentStationId &&
              shiftName == currentShiftName &&
              sysId == currentSysId) {
            continue;
          }

          if (opId == operatorId) {
            return '$stnName - $shiftName';
          }
        }
      }
    }
    return null;
  }

  Future<void> _publishRosters() async {
    if (_isPastDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Past shift duties are locked. You cannot publish for past dates.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final stations = ref.read(stationsListProvider).value ?? [];
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Filter by single selected station OR all stations depending on checkbox
    final targetStations = _publishAllStations
        ? stations
        : stations.where((s) => s.id == _selectedStationId).toList();

    if (targetStations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a station to publish.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final dateRosters = _dateRosterTree[formattedDate];
    if (dateRosters == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please assign staff members before publishing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    bool hasPublishedAny = false;

    final List<Future<void>> publishTasks = [];

    for (final stn in targetStations) {
      final stationRosters = dateRosters[stn.id];
      if (stationRosters == null) continue;

      final shifts = _getShiftsForStation(stn);

      for (final tmpl in shifts) {
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

            _stationLatestTemplate.putIfAbsent(stn.id, () => {});
            _stationLatestTemplate[stn.id]!.putIfAbsent(
              tmpl.shiftName,
              () => {},
            );
            _stationLatestTemplate[stn.id]![tmpl.shiftName]![sysId] = {
              'operator_id': opId,
              'is_ot': data['is_ot'] ?? false,
            };
          }
        });

        if (rawAssignments.isNotEmpty) {
          hasPublishedAny = true;
          publishTasks.add(
            ref
                .read(shiftActionNotifierProvider.notifier)
                .publishShift(
                  stationId: stn.id,
                  shiftName: tmpl.shiftName,
                  dutyDate: formattedDate,
                  startTime: tmpl.startTime,
                  endTime: tmpl.endTime,
                  dailyAmount: stn.defaultFixedAmount,
                  rawAssignments: rawAssignments,
                ),
          );
        }
      }
    }

    if (publishTasks.isNotEmpty) {
      await Future.wait(publishTasks);
    }

    if (!hasPublishedAny) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please assign at least one staff member before publishing.',
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
        SnackBar(
          content: Text(
            _publishAllStations
                ? 'All Stations Published Successfully for $formattedDate!'
                : 'Station Roster Published Successfully for $formattedDate!',
          ),
          backgroundColor: const Color(0xFF059669),
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
                    // Dynamic Date Card with Highlighting
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _isFutureDate
                            ? const Color(0xFFF0FDF4)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isFutureDate
                              ? const Color(0xFF86EFAC)
                              : (_isPastDate
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFFE2E8F0)),
                          width: _isFutureDate ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isFutureDate
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.calendar_today_rounded,
                                  color: _isFutureDate
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF1E3A8A),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Roster Duty Date',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      if (_isFutureDate) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF16A34A),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Upcoming Date',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    DateFormat(
                                      'EEEE, dd MMM yyyy',
                                    ).format(_selectedDate),
                                    style: TextStyle(
                                      color: _isPastDate
                                          ? Colors.red.shade700
                                          : (_isFutureDate
                                                ? const Color(0xFF15803D)
                                                : Colors.grey.shade600),
                                      fontWeight: (_isPastDate || _isFutureDate)
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
                              side: BorderSide(
                                color: _isFutureDate
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF1E3A8A),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 60),
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

                    // Past Date Block Banner
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
                                'This shift date has already passed. Duties are locked and cannot be published or altered.',
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
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'No stations found. Create a station first.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          );
                        }

                        _selectedStationId ??= stations.first.id;
                        final currentStation = stations.firstWhere(
                          (s) => s.id == _selectedStationId,
                          orElse: () => stations.first,
                        );

                        final shifts = _getShiftsForStation(currentStation);
                        final systems = _getSystemsForStation(currentStation);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Select Station to Configure',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                prefixIcon: Icon(
                                  Icons.subway_rounded,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              value: currentStation.id,
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
                                  setState(() {
                                    _selectedStationId = id;
                                    _initStationRoster(stn);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),

                            // Checkbox for publishing single station vs all stations
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _publishAllStations
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _publishAllStations
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'Publish for ALL Stations simultaneously',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                                subtitle: Text(
                                  _publishAllStations
                                      ? 'Will publish duties for all ${stations.length} stations on ${DateFormat('dd MMM').format(_selectedDate)}'
                                      : 'Only publishing duty roster for ${currentStation.name}',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                value: _publishAllStations,
                                activeColor: const Color(0xFF1E3A8A),
                                onChanged: _isPastDate
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _publishAllStations = val ?? false;
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(height: 16),

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
                                    '${currentStation.name} TOM Counters & Shifts',
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
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: shifts.length,
                                  itemBuilder: (ctx, shiftIdx) {
                                    final tmpl = shifts[shiftIdx];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
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
                                                    fontWeight: FontWeight.bold,
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
                                                      color: Color(0xFF2563EB),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const Divider(
                                              height: 18,
                                              color: Color(0xFFF1F5F9),
                                            ),
                                            ...systems.map((sys) {
                                              final curData =
                                                  _dateRosterTree[dateKey]?[currentStation
                                                      .id]?[tmpl.shiftName]?[sys
                                                      .id];
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
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
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
                                                                horizontal: 10,
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
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                          ...staffList.map((s) {
                                                            final assignedInfo =
                                                                _getAssignedDutyLabel(
                                                                  operatorId:
                                                                      s.id,
                                                                  dateKey:
                                                                      dateKey,
                                                                  allStations:
                                                                      stations,
                                                                  currentStationId:
                                                                      currentStation
                                                                          .id,
                                                                  currentShiftName:
                                                                      tmpl.shiftName,
                                                                  currentSysId:
                                                                      sys.id,
                                                                );

                                                            final isAssignedElsewhere =
                                                                assignedInfo !=
                                                                null;

                                                            return DropdownMenuItem(
                                                              value: s.id,
                                                              child: Text(
                                                                isAssignedElsewhere
                                                                    ? '${s.fullName} ($assignedInfo)'
                                                                    : s.fullName,
                                                                style: TextStyle(
                                                                  fontSize:
                                                                      12.5,
                                                                  color:
                                                                      isAssignedElsewhere
                                                                      ? const Color(
                                                                          0xFFD97706,
                                                                        )
                                                                      : const Color(
                                                                          0xFF1E293B,
                                                                        ),
                                                                  fontWeight:
                                                                      isAssignedElsewhere
                                                                      ? FontWeight
                                                                            .bold
                                                                      : FontWeight
                                                                            .normal,
                                                                ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            );
                                                          }),
                                                        ],
                                                        onChanged: _isPastDate
                                                            ? null
                                                            : (val) {
                                                                setState(() {
                                                                  _dateRosterTree[dateKey]![currentStation
                                                                          .id]![tmpl
                                                                          .shiftName]![sys
                                                                          .id]!['operator_id'] =
                                                                      val;
                                                                  _stationLatestTemplate
                                                                      .putIfAbsent(
                                                                        currentStation
                                                                            .id,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  _stationLatestTemplate[currentStation
                                                                          .id]!
                                                                      .putIfAbsent(
                                                                        tmpl.shiftName,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  _stationLatestTemplate[currentStation
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
                                                                _dateRosterTree[dateKey]![currentStation
                                                                        .id]![tmpl
                                                                        .shiftName]![sys
                                                                        .id]!['is_ot'] =
                                                                    updatedOt;

                                                                _stationLatestTemplate
                                                                    .putIfAbsent(
                                                                      currentStation
                                                                          .id,
                                                                      () => {},
                                                                    );
                                                                _stationLatestTemplate[currentStation
                                                                        .id]!
                                                                    .putIfAbsent(
                                                                      tmpl.shiftName,
                                                                      () => {},
                                                                    );
                                                                _stationLatestTemplate[currentStation
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
                                                                FontWeight.bold,
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
                              loading: () => const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ),
                              error: (e, _) => Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Failed to load staff: $e',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
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
                            : (_publishAllStations
                                  ? const Color(0xFF047857)
                                  : const Color(0xFF1E3A8A)),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(
                        _publishAllStations
                            ? Icons.done_all_rounded
                            : Icons.send_rounded,
                      ),
                      onPressed: (_isPastDate || actionState.isLoading)
                          ? null
                          : _publishRosters,
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
                                  : (_publishAllStations
                                        ? 'Publish ALL Stations Roster'
                                        : 'Publish Station Shift Roster'),
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
