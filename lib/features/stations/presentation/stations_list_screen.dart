import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/features/reports/presentation/form_t_excel_generator.dart';
import 'station_provider.dart';
import 'create_edit_station_screen.dart';

class StationsListScreen extends ConsumerStatefulWidget {
  const StationsListScreen({super.key});

  @override
  ConsumerState<StationsListScreen> createState() => _StationsListScreenState();
}

class _StationsListScreenState extends ConsumerState<StationsListScreen> {
  String? _downloadingStationId;

  Future<void> _exportStationReport(
    String stationId,
    String stationName,
  ) async {
    setState(() => _downloadingStationId = stationId);
    try {
      await FormTExcelGenerator.generateAndDownloadExcel(
        stationId: stationId,
        stationName: stationName,
        selectedMonth: DateTime.now(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Form 'T' downloaded for $stationName"),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingStationId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(stationsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        color: const Color(0xFF1E3A8A),
        onRefresh: () async => ref.invalidate(stationsListProvider),
        child: stationsAsync.when(
          data: (stations) {
            if (stations.isEmpty) {
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
                            Icons.subway_outlined,
                            size: 48,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No stations registered yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap + below to add your first metro station',
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

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: stations.length,
              itemBuilder: (context, idx) {
                final s = stations[idx];
                final isDownloading = _downloadingStationId == s.id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.subway_rounded,
                                    color: Color(0xFF1E3A8A),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.name,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      'Geofence: ${s.punchRadiusMeters}m radius',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: "Download Form 'T' Excel",
                                  icon: isDownloading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF059669),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.file_download_outlined,
                                          color: Color(0xFF059669),
                                        ),
                                  onPressed: isDownloading
                                      ? null
                                      : () =>
                                            _exportStationReport(s.id, s.name),
                                ),
                                IconButton(
                                  tooltip: 'Edit Station',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Color(0xFF2563EB),
                                    size: 20,
                                  ),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CreateEditStationScreen(station: s),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete Station',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Station'),
                                        content: Text(
                                          'Delete station ${s.name}? This will remove associated shifts and assignments.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
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
                                            stationActionNotifierProvider
                                                .notifier,
                                          )
                                          .deleteStation(s.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 18, color: Color(0xFFF1F5F9)),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.desktop_windows_outlined,
                                    size: 13,
                                    color: Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${s.operatingSystems.length} TOM Counters',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${s.shiftTemplates.length} Shift Plans',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
          ),
          error: (e, _) => Center(child: Text('Error loading stations: $e')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateEditStationScreen()),
        ),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text(
          'Add Station',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
