import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/core/utils/display_formatters.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';
import 'package:metro_shift_roster/features/staff/presentation/staff_provider.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'shift_provider.dart';

class CreateEditShiftScreen extends ConsumerStatefulWidget {
  final String? initialStationId;
  final String? initialDutyDate;
  final String? initialShiftName;
  final String? initialShiftId;
  const CreateEditShiftScreen({
    super.key,
    this.initialStationId,
    this.initialDutyDate,
    this.initialShiftName,
    this.initialShiftId,
  });

  @override
  ConsumerState<CreateEditShiftScreen> createState() =>
      _CreateEditShiftScreenState();
}

class _CreateEditShiftScreenState extends ConsumerState<CreateEditShiftScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedStationId;
  DateTime _selectedDate = DateTime.now();
  bool get _singleShiftEdit =>
      widget.initialShiftName != null && widget.initialShiftName!.trim().isNotEmpty;
  bool _isLoadingExisting = false;
  bool _publishAllStations = false;
  bool _isPublishingRosters = false;
  String? _singleEditTemplateId;
  final Map<String, String> _shiftIdsByRosterKey = {};

  // [dateString] -> [stationId] -> [exact template id] -> [operatingSystemId] -> {operator_id, is_ot}
  final Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>>
  _dateRosterTree = {};

  // Persistent excluded/deleted TOM counters per station and exact shift template.
  // Exact scope key = duty date + station + exact shift template.
  final Map<String, Set<String>> _excludedSystems = {};

  // Latest known assignments per station and exact shift template.
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _stationLatestTemplate = {};

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.initialStationId;
    if (widget.initialDutyDate != null) {
      final parsed = DateTime.tryParse(widget.initialDutyDate!);
      if (parsed != null) _selectedDate = parsed;
    }
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

  String _rosterKey(StationShiftTemplate tmpl) =>
      tmpl.id.isNotEmpty
          ? tmpl.id
          : '${tmpl.stationId}|${tmpl.shiftName}|${tmpl.startTime}|${tmpl.endTime}';

  String _rosterScopeKey(String dateKey, String stationId, String templateKey) =>
      '$dateKey|$stationId|$templateKey';

  Future<void> _loadExistingAssignments() async {
    setState(() => _isLoadingExisting = true);
    try {
      // Reuse the already-loaded scoped roster when possible. This avoids
      // a second full roster request when opening a shift for editing.
      final shifts = await ref.read(supervisorShiftsProvider.future);

      final sortedShifts = List.of(shifts)
        ..sort((a, b) {
          var c = a.dutyDate.compareTo(b.dutyDate);
          if (c != 0) return c;
          c = a.stationId.compareTo(b.stationId);
          if (c != 0) return c;
          c = a.shiftName.compareTo(b.shiftName);
          if (c != 0) return c;
          c = a.startTime.compareTo(b.startTime);
          if (c != 0) return c;
          c = a.endTime.compareTo(b.endTime);
          if (c != 0) return c;
          return a.id.compareTo(b.id);
        });

      _dateRosterTree.clear();
      _excludedSystems.clear();
      _stationLatestTemplate.clear();
      _shiftIdsByRosterKey.clear();
      _singleEditTemplateId = null;

      final stations = ref.read(stationsListProvider).value ?? [];

      for (final s in sortedShifts) {
        // In single-shift edit mode, keep loading the full day's scoped roster
        // into _dateRosterTree so operator dropdowns can show where an operator
        // is already assigned (for example, "Venky (BRCS - B)"). The UI still
        // limits the visible shift/template to the one being edited via
        // _getShiftsForStation().

        final station = stations.where((st) => st.id == s.stationId).isNotEmpty
            ? stations.firstWhere((st) => st.id == s.stationId)
            : null;
        if (station == null) continue;

        // Match this DB shift to one exact station template. The occurrence
        // counter makes duplicate templates with the same name/time distinct.
        final allTemplates = _getShiftsForStation(station, ignoreSingleEdit: true);
        final candidates = allTemplates.where((t) =>
            t.shiftName == s.shiftName &&
            t.startTime == s.startTime &&
            t.endTime == s.endTime).toList();
        String? templateKey;
        if (s.templateId != null && s.templateId!.isNotEmpty) {
          final exactTemplate = candidates.where((t) => t.id == s.templateId).toList();
          if (exactTemplate.isNotEmpty) templateKey = _rosterKey(exactTemplate.first);
        }
        if (templateKey == null) {
          for (final candidate in candidates) {
            final key = _rosterKey(candidate);
            final scope = _rosterScopeKey(s.dutyDate, s.stationId, key);
            if (!_shiftIdsByRosterKey.containsKey(scope)) {
              templateKey = key;
              break;
            }
          }
        }
        templateKey ??= candidates.isNotEmpty ? _rosterKey(candidates.first) : null;
        if (templateKey == null) continue;

        final scopeKey = _rosterScopeKey(s.dutyDate, s.stationId, templateKey);
        _shiftIdsByRosterKey[scopeKey] = s.id;
        if (widget.initialShiftId == s.id) _singleEditTemplateId = templateKey;

        _dateRosterTree.putIfAbsent(s.dutyDate, () => {});
        _dateRosterTree[s.dutyDate]!.putIfAbsent(s.stationId, () => {});
        _dateRosterTree[s.dutyDate]![s.stationId]!.putIfAbsent(
          templateKey,
          () => {},
        );

        final selectedDateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
        if (s.dutyDate == selectedDateKey) {
          _stationLatestTemplate.putIfAbsent(s.stationId, () => {});
          _stationLatestTemplate[s.stationId]!.putIfAbsent(templateKey, () => {});
        }

        for (final a in s.assignments) {
          if (a.operatorId.isNotEmpty) {
            final assignmentData = {
              'operator_id': a.operatorId,
              'is_ot': a.isOt,
            };
            _dateRosterTree[s.dutyDate]![s.stationId]![templateKey]![a
                .operatingSystemId] = Map.from(assignmentData);
            if (s.dutyDate == selectedDateKey) {
              _stationLatestTemplate[s.stationId]![templateKey]![a
                  .operatingSystemId] = Map.from(assignmentData);
            }
          }
        }
      }

      for (final stn in stations) {
        _initStationRoster(stn);
      }

      if (_selectedStationId == null && stations.isNotEmpty) {
        _selectedStationId = stations.first.id;
      }
    } catch (_) {
    }
    if (mounted) {
      setState(() => _isLoadingExisting = false);
    }
  }

  List<StationShiftTemplate> _getShiftsForStation(StationModel stn, {bool ignoreSingleEdit = false}) {
    List<StationShiftTemplate> templates;
    if (stn.shiftTemplates.isNotEmpty) {
      templates = List.from(stn.shiftTemplates);
    } else {
      final suffix = stn.id.length >= 12
          ? stn.id.substring(stn.id.length - 12)
          : stn.id.padLeft(12, '0');
      templates = [
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
    templates.sort((a, b) {
      final comp = a.startTime.compareTo(b.startTime);
      return comp != 0 ? comp : a.shiftName.compareTo(b.shiftName);
    });
    if (_singleShiftEdit && !ignoreSingleEdit) {
      if (_singleEditTemplateId != null) {
        templates = templates.where((t) => _rosterKey(t) == _singleEditTemplateId).toList();
      } else {
        templates = templates.where((t) => t.shiftName == widget.initialShiftName).toList();
      }
    }
    return templates;
  }

  List<StationOperatingSystemModel> _getSystemsForStation(StationModel stn) {
    List<StationOperatingSystemModel> systems;
    if (stn.operatingSystems.isNotEmpty) {
      systems = List.from(stn.operatingSystems);
    } else {
      final suffix = stn.id.length >= 12
          ? stn.id.substring(stn.id.length - 12)
          : stn.id.padLeft(12, '0');
      systems = [
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
    systems.sort((a, b) => a.systemName.compareTo(b.systemName));
    return systems;
  }

  void _initStationRoster(StationModel stn) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _dateRosterTree.putIfAbsent(dateKey, () => {});
    _dateRosterTree[dateKey]!.putIfAbsent(stn.id, () => {});

    final shifts = _getShiftsForStation(stn);
    final systems = _getSystemsForStation(stn);

    for (final tmpl in shifts) {
      final rosterKey = _rosterKey(tmpl);
      _dateRosterTree[dateKey]![stn.id]!.putIfAbsent(rosterKey, () => {});

      for (int i = 0; i < systems.length; i++) {
        final sys = systems[i];
        final existing =
            _dateRosterTree[dateKey]![stn.id]![rosterKey]?[sys.id];

        if (existing == null) {
          // An unassigned counter must stay unassigned. Never carry an
          // operator from another date/shift merely because the time is the
          // same. Assignments belong to one exact station + shift + TOM.
          _dateRosterTree[dateKey]![stn.id]![rosterKey]![sys.id] = {
            'operator_id': null,
            'is_ot': false,
          };
        }
      }
    }
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
      _stationLatestTemplate.clear();
    });

    final dateKey = DateFormat('yyyy-MM-dd').format(newDate);
    final stations = ref.read(stationsListProvider).value ?? [];
    for (final stn in stations) {
      _initStationRoster(stn);
      final shifts = _dateRosterTree[dateKey]?[stn.id] ?? {};
      for (final entry in shifts.entries) {
        final cache = <String, Map<String, dynamic>>{};
        for (final sysEntry in entry.value.entries) {
          final data = sysEntry.value;
          if (data['operator_id'] != null && data['operator_id'].toString().isNotEmpty) {
            cache[sysEntry.key] = Map<String, dynamic>.from(data);
          }
        }
        if (cache.isNotEmpty) {
          _stationLatestTemplate.putIfAbsent(stn.id, () => {});
          _stationLatestTemplate[stn.id]![entry.key] = cache;
        }
      }
    }
  }

  String? _getAssignedDutyLabel({
    required String operatorId,
    required String dateKey,
    required List<StationModel> allStations,
    required String currentStationId,
    required String currentShiftKey,
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
              shiftName == currentShiftKey &&
              sysId == currentSysId) {
            continue;
          }

          if (opId == operatorId) {
            return '$stnName - ${shiftName == currentShiftKey ? 'Current shift' : 'Other shift'}';
          }
        }
      }
    }
    return null;
  }

  Future<void> _publishRosters() async {
    if (_isPublishingRosters) return;
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
    if (mounted) setState(() => _isPublishingRosters = true);

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
      if (mounted) setState(() => _isPublishingRosters = false);
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
      if (mounted) setState(() => _isPublishingRosters = false);
      return;
    }

    bool hasPublishedAny = false;
    final List<Future<void> Function()> publishTasks = [];

    for (final stn in targetStations) {
      final stationRosters = dateRosters[stn.id];
      if (stationRosters == null) continue;

      final shifts = _getShiftsForStation(stn);

      for (final tmpl in shifts) {
        final rosterKey = _rosterKey(tmpl);
        final shiftAssignments = stationRosters[rosterKey];
        if (shiftAssignments == null) continue;

        final excludedSet = _excludedSystems[_rosterScopeKey(formattedDate, stn.id, rosterKey)] ?? <String>{};

        final List<Map<String, dynamic>> rawAssignments = [];
        final List<String> clearedSystemIds = [];
        shiftAssignments.forEach((sysId, data) {
          if (excludedSet.contains(sysId)) return;

          final opId = data['operator_id'];
          if (opId != null && opId.toString().trim().isNotEmpty) {
            rawAssignments.add({
              'operating_system_id': sysId,
              'operator_id': opId,
              'is_ot': data['is_ot'] ?? false,
            });

            _stationLatestTemplate.putIfAbsent(stn.id, () => {});
            _stationLatestTemplate[stn.id]!.putIfAbsent(
              rosterKey,
              () => {},
            );
            _stationLatestTemplate[stn.id]![rosterKey]![sysId] = {
              'operator_id': opId,
              'is_ot': data['is_ot'] ?? false,
            };
          } else {
            // Explicitly unassign this TOM from THIS shift only.
            clearedSystemIds.add(sysId);
          }
        });

        if (rawAssignments.isNotEmpty ||
            clearedSystemIds.isNotEmpty ||
            excludedSet.isNotEmpty) {
          hasPublishedAny = true;
          publishTasks.add(() => ref
                .read(shiftActionNotifierProvider.notifier)
                .publishShift(
                  stationId: stn.id,
                  shiftName: tmpl.shiftName,
                  templateId: tmpl.id.isNotEmpty ? tmpl.id : null,
                  dutyDate: formattedDate,
                  startTime: tmpl.startTime,
                  endTime: tmpl.endTime,
                  dailyAmount: stn.defaultFixedAmount,
                  rawAssignments: rawAssignments,
                  existingShiftId: _shiftIdsByRosterKey[_rosterScopeKey(formattedDate, stn.id, rosterKey)],
                  clearedOperatingSystemIds: clearedSystemIds,
                  removedOperatingSystemIds: excludedSet.toList(),
                ));
        }
      }
    }

    if (publishTasks.isNotEmpty) {
      // Publish independent station/shift writes concurrently. The previous
      // sequential loop made multi-shift publishing unnecessarily slow.
      await Future.wait(publishTasks.map((task) => task()));
    }

    if (!hasPublishedAny) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please assign at least one staff member to an active counter before publishing.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      if (mounted) setState(() => _isPublishingRosters = false);
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
      if (mounted) setState(() => _isPublishingRosters = false);
      Navigator.pop(context, formattedDate);
    } else if (mounted) {
      setState(() => _isPublishingRosters = false);
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
                      padding: const EdgeInsets.all(12),
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    const Text(
                                      'Roster Duty Date',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (_isFutureDate)
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
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat(
                                    'EEEE, dd MMM yyyy',
                                  ).format(_selectedDate),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _isFutureDate
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF1E3A8A),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _singleShiftEdit ? null : () async {
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
                            child: Text(
                              'Change Date',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isFutureDate
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF1E3A8A),
                              ),
                            ),
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
                              onChanged: _singleShiftEdit ? null : (id) {
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
                                      ? 'Will publish duties for all ${stations.length} stations on ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'
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
                                    final rosterKey = _rosterKey(tmpl);

                                    final excludedSet =
                                        _excludedSystems[_rosterScopeKey(
                                          dateKey,
                                          currentStation.id,
                                          rosterKey,
                                        )] ??
                                        <String>{};
                                    final deletedSystems = systems
                                        .where(
                                          (s) => excludedSet.contains(s.id),
                                        )
                                        .toList();

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
                                                    '${formatDisplayTime(tmpl.startTime)} - ${formatDisplayTime(tmpl.endTime)}',
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
                                            ...systems.where((s) => !excludedSet.contains(s.id)).map((
                                              sys,
                                            ) {
                                              final curData =
                                                  _dateRosterTree[dateKey]?[currentStation
                                                      .id]?[rosterKey]?[sys
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
                                                    // Cross Delete Icon beside TOM
                                                    InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      onTap: _isPastDate
                                                          ? null
                                                          : () {
                                                              setState(() {
                                                                final scopeKey = _rosterScopeKey(
                                                                  dateKey,
                                                                  currentStation.id,
                                                                  rosterKey,
                                                                );
                                                                _excludedSystems
                                                                    .putIfAbsent(
                                                                  scopeKey,
                                                                  () => <String>{},
                                                                )
                                                                    .add(sys.id);

                                                                // Preserve the current
                                                                // assignment so Restore TOM
                                                                // can put the same operator
                                                                // back automatically.
                                                                final currentAssignment =
                                                                    _dateRosterTree[dateKey]?[currentStation
                                                                        .id]?[rosterKey]?[sys
                                                                        .id];

                                                                _stationLatestTemplate
                                                                    .putIfAbsent(
                                                                      currentStation
                                                                          .id,
                                                                      () => {},
                                                                    );
                                                                _stationLatestTemplate[currentStation
                                                                        .id]!
                                                                    .putIfAbsent(
                                                                      rosterKey,
                                                                      () => {},
                                                                    );
                                                                _stationLatestTemplate[currentStation
                                                                    .id]![rosterKey]![sys
                                                                    .id] = {
                                                                  'operator_id':
                                                                      currentAssignment?['operator_id'],
                                                                  'is_ot':
                                                                      currentAssignment?['is_ot'] ??
                                                                      false,
                                                                };

                                                                _dateRosterTree[dateKey]?[currentStation
                                                                        .id]?[rosterKey]?[sys
                                                                        .id]?['operator_id'] =
                                                                    null;
                                                              });
                                                            },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.only(
                                                              right: 4,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .red
                                                                  .shade50,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Icon(
                                                          Icons.close_rounded,
                                                          color: Colors
                                                              .red
                                                              .shade600,
                                                          size: 15,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 58,
                                                      child: Text(
                                                        sys.systemName,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12,
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
                                                        isExpanded: true,
                                                        isDense: true,
                                                        decoration: const InputDecoration(
                                                          contentPadding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 6,
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
                                                            fontSize: 11.5,
                                                          ),
                                                        ),
                                                        items: [
                                                          const DropdownMenuItem(
                                                            value: null,
                                                            child: Text(
                                                              '-- Unassigned --',
                                                              style: TextStyle(
                                                                fontSize: 11.5,
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
                                                                  currentShiftKey:
                                                                      rosterKey,
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
                                                                  fontSize: 12,
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
                                                                          .id]![rosterKey]![sys
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
                                                                        rosterKey,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  _stationLatestTemplate[currentStation
                                                                      .id]![rosterKey]![sys
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
                                                    const SizedBox(width: 6),
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
                                                                        .id]![rosterKey]![sys
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
                                                                      rosterKey,
                                                                      () => {},
                                                                    );
                                                                _stationLatestTemplate[currentStation
                                                                    .id]![rosterKey]![sys
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
                                                              horizontal: 8,
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

                                            // "+ Recover TOM" Action chips for deleted counters
                                            if (deletedSystems.isNotEmpty &&
                                                !_isPastDate)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8.0,
                                                ),
                                                child: Wrap(
                                                  spacing: 8,
                                                  children: deletedSystems.map((
                                                    dSys,
                                                  ) {
                                                    return ActionChip(
                                                      avatar: const Icon(
                                                        Icons.add_rounded,
                                                        size: 16,
                                                        color: Color(
                                                          0xFF1E3A8A,
                                                        ),
                                                      ),
                                                      label: Text(
                                                        'Restore ${dSys.systemName}',
                                                        style: const TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF1E3A8A,
                                                          ),
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          const Color(
                                                            0xFFEFF6FF,
                                                          ),
                                                      side: const BorderSide(
                                                        color: Color(
                                                          0xFFBFDBFE,
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          // Restore only the TOM that the
                                                          // supervisor explicitly deleted.
                                                          _excludedSystems[_rosterScopeKey(
                                                                  dateKey,
                                                                  currentStation.id,
                                                                  rosterKey,
                                                                )]
                                                              ?.remove(dSys.id);

                                                          // Restore its previous operator
                                                          // assignment, if one was saved.
                                                          final previousAssignment =
                                                              _stationLatestTemplate[currentStation
                                                                  .id]?[rosterKey]?[dSys
                                                                  .id];

                                                          _dateRosterTree[dateKey]![currentStation
                                                              .id]![rosterKey]![dSys
                                                              .id] = {
                                                            'operator_id':
                                                                previousAssignment?['operator_id'],
                                                            'is_ot':
                                                                previousAssignment?['is_ot'] ??
                                                                false,
                                                          };
                                                        });
                                                      },
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
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
                      onPressed: (_isPastDate || actionState.isLoading || _isPublishingRosters)
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
