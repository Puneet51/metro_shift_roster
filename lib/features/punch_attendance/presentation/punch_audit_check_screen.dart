import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/punch_attendance/presentation/attendance_provider.dart';
import 'package:metro_shift_roster/features/punch_attendance/presentation/face_punch_screen.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';

class PunchAuditCheckScreen extends ConsumerWidget {
  const PunchAuditCheckScreen({super.key});

  Future<void> _handleAutoNearestPunch(
    BuildContext context,
    WidgetRef ref,
    bool isPunchIn,
    String? sessionId,
  ) async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;

    // Await station list
    List<StationModel> stations = ref.read(stationsListProvider).value ?? [];
    if (stations.isEmpty) {
      stations = await ref.read(stationsListProvider.future);
    }

    if (stations.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No stations registered. Please contact your supervisor.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Automatically locate nearest station based on device coordinates
    StationModel targetStation = stations.first;
    try {
      Position? currentPos = await Geolocator.getLastKnownPosition();
      currentPos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      );

      double minDistance = double.infinity;
      for (final stn in stations) {
        final d = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          stn.latitude,
          stn.longitude,
        );
        if (d < minDistance) {
          minDistance = d;
          targetStation = stn;
        }
      }
    } catch (_) {}

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FacePunchScreen(
            station: targetStation,
            isPunchIn: isPunchIn,
            activeSessionId: sessionId,
          ),
        ),
      );
    }
  }

  Widget _buildStatusChip(Map<String, dynamic> record) {
    final statusRaw = (record['status'] ?? '').toString().toLowerCase();
    final punchInStr = record['punch_in_time'] ?? record['punch_in_at'];
    final punchOutStr = record['punch_out_time'] ?? record['punch_out_at'];

    final punchIn = punchInStr != null
        ? DateTime.tryParse(punchInStr.toString())
        : null;
    final punchOut = punchOutStr != null
        ? DateTime.tryParse(punchOutStr.toString())
        : null;

    int durationSeconds =
        (record['duty_duration_seconds'] as num?)?.toInt() ?? 0;
    if (durationSeconds == 0 && punchIn != null && punchOut != null) {
      durationSeconds = punchOut.difference(punchIn).inSeconds;
    }

    String label;
    Color bg;
    Color fg;

    if (statusRaw == 'auto_absent') {
      // The server has already closed this forgotten punch-in.
      // Never interpret a null punch_out_at as ON DUTY for auto_absent.
      label = 'ABSENT';
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
    } else if (punchIn != null && punchOut == null) {
      label = 'ON DUTY';
      bg = const Color(0xFFEFF6FF);
      fg = const Color(0xFF1E3A8A);
    } else if (punchIn != null && punchOut != null) {
      // Must be >= 7 hours 50 minutes (28,200 seconds)
      if (statusRaw == 'present' || durationSeconds >= 28200) {
        label = 'PRESENT';
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
      } else {
        label = 'ABSENT';
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
      }
    } else {
      label = 'ABSENT';
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(punchAuditListProvider);
    final activeSessionAsync = ref.watch(activePunchSessionProvider);
    final isAlreadyCompleted =
        ref.watch(hasCompletedPunchTodayProvider).value ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active Shift Card
            activeSessionAsync.when(
              data: (activeSession) {
                // Only a session explicitly marked in_progress is active.
                // auto_absent sessions are already closed by the database
                // finalizer and must never be shown as ON DUTY.
                final activeStatus = activeSession?['status']
                    ?.toString()
                    .toLowerCase();
                final activePunchOut = activeSession?['punch_out_at'] ??
                    activeSession?['punch_out_time'];
                final isClosedStatus = activeStatus == 'auto_absent' ||
                    activeStatus == 'completed' ||
                    activeStatus == 'rejected';
                final isPunchedIn = activeSession != null &&
                    activePunchOut == null &&
                    !isClosedStatus;


                DateTime? punchInTime;
                if (isPunchedIn && activeSession['punch_in_time'] != null) {
                  punchInTime = DateTime.tryParse(
                    activeSession['punch_in_time'].toString(),
                  );
                }

                final stationMap =
                    activeSession?['stations'] as Map<String, dynamic>?;
                final stationName = stationMap?['name'] ?? 'Nearest Station';

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPunchedIn
                          ? const Color(0xFF2563EB).withOpacity(0.4)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPunchedIn
                                    ? const Color(0xFFEFF6FF)
                                    : const Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPunchedIn
                                    ? Icons.timer_outlined
                                    : Icons.radio_button_unchecked,
                                color: isPunchedIn
                                    ? const Color(0xFF1E3A8A)
                                    : const Color(0xFF94A3B8),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPunchedIn
                                        ? 'Duty Status: ON DUTY'
                                        : 'Duty Status: Not Punched In',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15.5,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    isPunchedIn
                                        ? 'Shift active • Night-shift auto date calculated'
                                        : 'Ready for duty punch in (Assigned / Unassigned)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isPunchedIn) ...[
                          const Divider(height: 24, color: Color(0xFFF1F5F9)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'STATION',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    stationName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              if (punchInTime != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'PUNCH IN TIME (IST)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat(
                                        'hh:mm a',
                                      ).format(punchInTime.toLocal()),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (isAlreadyCompleted && !isPunchedIn)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF86EFAC),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF16A34A),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Today's Shift Completed (1 Duty Recorded)",
                                  style: TextStyle(
                                    color: Color(0xFF166534),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPunchedIn
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(
                              Icons.camera_alt_rounded,
                              size: 20,
                            ),
                            label: Text(
                              isPunchedIn ? 'Face Punch Out' : 'Face Punch In',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            onPressed: () => _handleAutoNearestPunch(
                              context,
                              ref,
                              !isPunchedIn,
                              activeSession?['id']?.toString(),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              loading: () =>
                  const LinearProgressIndicator(color: Color(0xFF1E3A8A)),
              error: (_, __) => const SizedBox(),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Punch Logs (IST)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Last 30 Records',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Logs Listing
            auditAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No recorded punch logs yet.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final timeFormat = DateFormat('dd MMM yyyy, hh:mm a');

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final s = sessions[idx];
                    final stationData = s['stations'] as Map<String, dynamic>?;
                    final stationName = stationData?['name'] ?? 'Station';

                    DateTime? inTime;
                    if (s['punch_in_time'] != null) {
                      inTime = DateTime.tryParse(s['punch_in_time'].toString());
                    }

                    DateTime? outTime;
                    if (s['punch_out_time'] != null) {
                      outTime = DateTime.tryParse(
                        s['punch_out_time'].toString(),
                      );
                    }

                    final statusRaw = (s['status'] ?? '')
                        .toString()
                        .toLowerCase();
                    final isAutoAbsent = statusRaw == 'auto_absent';

                    return Container(
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
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stationName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'In: ${inTime != null ? timeFormat.format(inTime.toLocal()) : "—"}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'Out: ${outTime != null ? timeFormat.format(outTime.toLocal()) : (isAutoAbsent ? "Auto Closed" : "In Progress")}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: outTime != null
                                          ? Colors.grey.shade600
                                          : (isAutoAbsent
                                                ? const Color(0xFFDC2626)
                                                : const Color(0xFFD97706)),
                                      fontWeight: outTime != null
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusChip(s),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                ),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ],
        ),
      ),
    );
  }
}
