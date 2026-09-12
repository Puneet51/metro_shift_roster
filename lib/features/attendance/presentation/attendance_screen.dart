import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/core/utils/display_formatters.dart';
import 'package:metro_shift_roster/features/reports/presentation/form_t_excel_generator.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'attendance_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  final bool supervisorReportMode;
  const AttendanceScreen({super.key, this.supervisorReportMode = false});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _stationId;
  bool _downloading = false;
  int? _completedDutyCount;
  List<Map<String, dynamic>> _completedOperators = [];
  bool _loadingCompletedOperators = false;

  Color _bg(String status) {
    switch (status) {
      case 'present': return const Color(0xFFECFDF5);
      case 'week_off': return const Color(0xFFFFFBEB);
      default: return const Color(0xFFFEF2F2);
    }
  }
  Color _fg(String status) {
    switch (status) {
      case 'present': return const Color(0xFF059669);
      case 'week_off': return const Color(0xFFD97706);
      default: return const Color(0xFFDC2626);
    }
  }
  String _label(String status) {
    switch (status) {
      case 'present': return 'PRESENT';
      case 'week_off': return 'WEEK OFF';
      default: return 'ABSENT';
    }
  }

  Future<void> _refreshCompletedCount() async {
    final stationId = _stationId;
    if (stationId == null || stationId.isEmpty) {
      if (mounted) {
        setState(() {
          _completedDutyCount = null;
          _completedOperators = [];
          _loadingCompletedOperators = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loadingCompletedOperators = true);
    try {
      final rows = await ref.read(attendanceRepositoryProvider).getCompletedDutyOperators(
        stationId: stationId,
        selectedMonth: _selectedMonth,
      );
      if (mounted) {
        setState(() {
          _completedDutyCount = rows.length;
          _completedOperators = rows;
          _loadingCompletedOperators = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _completedDutyCount = null;
          _completedOperators = [];
          _loadingCompletedOperators = false;
        });
      }
    }
  }

  Future<void> _downloadReport() async {
    if (_stationId == null || _stationId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a station first.')));
      return;
    }
    final stations = ref.read(stationsListProvider).value ?? [];
    final station = stations.where((s) => s.id == _stationId).firstOrNull;
    if (station == null) return;
    setState(() => _downloading = true);
    try {
      await FormTExcelGenerator.generateAndDownloadExcel(
        stationId: station.id,
        stationName: station.name,
        selectedMonth: _selectedMonth,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Completed duty attendance downloaded for ${station.name} — ${DateFormat('MMMM yyyy').format(_selectedMonth)}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      helpText: 'Select any date in the month',
    );
    if (picked != null) {
      setState(() { _selectedMonth = DateTime(picked.year, picked.month); _completedDutyCount = null; });
      await _refreshCompletedCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(stationsListProvider);

    if (widget.supervisorReportMode) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: Colors.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Attendance Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              const Text('Download only completed operator duties for the selected month and station.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _pickMonth, icon: const Icon(Icons.calendar_month_outlined), label: Text(DateFormat('MMMM yyyy').format(_selectedMonth)))),
                const SizedBox(width: 10),
                Expanded(child: stationsAsync.when(
                  loading: () => const InputDecorator(decoration: InputDecoration(border: OutlineInputBorder()), child: Text('Loading stations...')),
                  error: (e, _) => InputDecorator(decoration: const InputDecoration(border: OutlineInputBorder()), child: Text('Station error')),
                  data: (stations) => DropdownButtonFormField<String>(
                    value: stations.any((s) => s.id == _stationId) ? _stationId : null,
                    decoration: const InputDecoration(labelText: 'Station', border: OutlineInputBorder()),
                    items: stations.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) async {
                      setState(() { _stationId = v; _completedDutyCount = null; });
                      await _refreshCompletedCount();
                    },
                  ),
                )),
              ]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _downloading ? null : _downloadReport,
                icon: _downloading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded),
                label: Text(_downloading ? 'Preparing Excel...' : 'Download Completed Duties Excel'),
              )),
            ]),
          ),
          Expanded(
            child: _stationId == null
                ? const Center(child: Text('Select month and station to see completed duties.', style: TextStyle(color: Color(0xFF64748B))))
                : _loadingCompletedOperators
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Text(
                            'Completed operator duties: ${_completedDutyCount ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 10),
                          if (_completedOperators.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 50),
                              child: Center(child: Text('No completed duties for this station and month.', style: TextStyle(color: Color(0xFF64748B)))),
                            )
                          else
                            ..._completedOperators.map((row) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFECFDF5),
                                  child: Icon(Icons.check_rounded, color: Color(0xFF059669)),
                                ),
                                title: Text(
                                  row['operator_name']?.toString() ?? 'Operator',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '${formatDisplayDate(row['duty_date']?.toString())} • ${row['shift_name'] ?? 'Duty'} • ${formatDisplayTime(row['start_time']?.toString())}-${formatDisplayTime(row['end_time']?.toString())}',
                                ),
                                trailing: row['is_ot'] == true
                                    ? const Chip(label: Text('OT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))
                                    : const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 20),
                              ),
                            )),
                        ],
                      ),
          ),
        ]),
      );
    }

    final attendance = ref.watch(operatorAttendanceProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(operatorAttendanceProvider),
        child: attendance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [const SizedBox(height: 180), Center(child: Text('Unable to load attendance: $e'))]),
          data: (rows) {
            if (rows.isEmpty) return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 180), Center(child: Text('No attendance records yet.'))]);
            return ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final row = rows[index]; final status = (row['status'] ?? 'absent').toString().toLowerCase();
                final station = row['stations']; final shift = row['shifts'];
                final stationName = station is Map ? (station['name']?.toString() ?? 'Station') : 'Station';
                final shiftName = shift is Map ? (shift['shift_name']?.toString() ?? 'Duty') : 'Duty';
                return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))), child: ListTile(
                  leading: CircleAvatar(backgroundColor: _bg(status), child: Icon(status == 'present' ? Icons.check_rounded : status == 'week_off' ? Icons.beach_access_rounded : Icons.close_rounded, color: _fg(status))),
                  title: Text('${formatDisplayDate(row['duty_date']?.toString())} • $stationName', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(shiftName),
                  trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: _bg(status), borderRadius: BorderRadius.circular(7)), child: Text(_label(status), style: TextStyle(color: _fg(status), fontWeight: FontWeight.bold, fontSize: 10))),
                ));
              },
            );
          },
        ),
      ),
    );
  }
}
