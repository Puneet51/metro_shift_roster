import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:metro_shift_roster/core/services/face_biometric_service.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';
import 'package:metro_shift_roster/features/punch_attendance/presentation/attendance_provider.dart';
import 'package:metro_shift_roster/features/profile/presentation/profile_screen.dart';

class FacePunchScreen extends ConsumerStatefulWidget {
  final StationModel station;
  final bool isPunchIn;
  final String? activeSessionId;

  const FacePunchScreen({
    super.key,
    required this.station,
    required this.isPunchIn,
    this.activeSessionId,
  });

  @override
  ConsumerState<FacePunchScreen> createState() => _FacePunchScreenState();
}

class _FacePunchScreenState extends ConsumerState<FacePunchScreen> {
  CameraController? _cameraController;
  late final FaceBiometricService _faceService;
  bool _isProcessing = false;
  bool _isDisposed = false;
  Position? _preloadedPosition;
  double? _currentDistanceToStation;

  @override
  void initState() {
    super.initState();
    _faceService = FaceBiometricService();
    _initFastCamera();
    _preWarmLocation();
  }

  Future<void> _preWarmLocation() async {
    try {
      _preloadedPosition = await Geolocator.getLastKnownPosition();
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      );
      if (!_isDisposed) {
        setState(() {
          _preloadedPosition = fresh;
          _currentDistanceToStation = Geolocator.distanceBetween(
            fresh.latitude,
            fresh.longitude,
            widget.station.latitude,
            widget.station.longitude,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _initFastCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted && !_isDisposed) setState(() {});
  }

  Future<void> _performFacePunch() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    setState(() => _isProcessing = true);

    try {
      final user = ref.read(authNotifierProvider).user;
      if (user == null) {
        throw Exception('Session expired. Please log in again.');
      }

      // 1. Biometric registration verification
      if (user.faceEmbedding == null || user.faceEmbedding!.isEmpty) {
        throw Exception(
          'Face profile not registered. Please register your face before punching.',
        );
      }

      // 2. Fetch high accuracy position
      Position? position = _preloadedPosition;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (_) {
        position ??= await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        throw Exception(
          'Unable to acquire GPS coordinates. Ensure location is turned on.',
        );
      }

      if (position.isMocked) {
        throw Exception('Fake / Mock GPS detected. Punch rejected.');
      }

      // 3. Strict 100-Meter Geofence check
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.station.latitude,
        widget.station.longitude,
      );

      setState(() => _currentDistanceToStation = distance);

      if (distance > 100.0) {
        throw Exception(
          'You are ${distance.toStringAsFixed(1)}m away from ${widget.station.name}. You must be within 100m to punch.',
        );
      }

      // 4. Capture photo and extract live face embedding
      final photo = await _cameraController!.takePicture();
      final liveEmbedding = await _faceService.extractFaceEmbeddingFromFile(
        photo.path,
      );

      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (liveEmbedding == null || liveEmbedding.isEmpty) {
        throw Exception(
          'No face detected. Ensure good lighting and keep your face inside the oval.',
        );
      }

      // 5. Strict biometric similarity match
      final similarity = _faceService.compareEmbeddings(
        liveEmbedding,
        user.faceEmbedding!,
      );

      if (similarity < 0.70) {
        throw Exception(
          'Face mismatch (${(similarity * 100).toStringAsFixed(1)}%). Biometric verification failed.',
        );
      }

      // 6. Invoke unified RPC via AttendanceRepository
      final repo = ref.read(attendanceRepositoryProvider);
      final Map<String, dynamic> res;

      if (widget.isPunchIn) {
        res = await repo.punchIn(
          stationId: widget.station.id,
          lat: position.latitude,
          lng: position.longitude,
          faceEmbedding: liveEmbedding,
        );
      } else {
        if (widget.activeSessionId == null || widget.activeSessionId!.isEmpty) {
          throw Exception(
            'No active punch-in session found to punch out from.',
          );
        }
        res = await repo.punchOut(
          sessionId: widget.activeSessionId!,
          lat: position.latitude,
          lng: position.longitude,
          faceEmbedding: liveEmbedding,
        );
      }

      if (res['success'] == true) {
        ref.invalidate(activePunchSessionProvider);
        ref.invalidate(operatorSummaryMetricsProvider);
        ref.invalidate(punchAuditListProvider);

        if (mounted) {
          final isPunchIn = widget.isPunchIn;
          final workedHours = res['hours_worked'];
          final isPresent = res['status'] == 'present';

          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    isPunchIn
                        ? Icons.check_circle_rounded
                        : (isPresent
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded),
                    color: isPunchIn
                        ? const Color(0xFF059669)
                        : (isPresent
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPunchIn ? 'Shift Started' : 'Shift Finished',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPunchIn
                        ? 'Punch In Verified — ON DUTY'
                        : (isPresent
                              ? 'Punch Out Verified — PRESENT'
                              : 'Punch Out Recorded — ABSENT (< 7h 50m)'),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isPunchIn
                          ? const Color(0xFF059669)
                          : (isPresent
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Station: ${widget.station.name}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  if (!isPunchIn && workedHours != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Hours Worked: $workedHours hrs',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception(res['error']?.toString() ?? 'Verification failed.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final isNotRegistered =
        user != null &&
        (!user.isFaceRegistered ||
            user.faceEmbedding == null ||
            user.faceEmbedding!.isEmpty);

    final bool isOutOfRange =
        _currentDistanceToStation != null && _currentDistanceToStation! > 100.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        title: Text(
          widget.isPunchIn ? 'Face Punch In' : 'Face Punch Out',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isNotRegistered
          ? Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.face_retouching_off,
                      size: 64,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Face Not Registered',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Biometric identification is mandatory. Please register your face profile before performing punch in/out.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.person, color: Colors.white),
                      label: const Text(
                        'Go to Profile to Register',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : (_cameraController == null ||
                !_cameraController!.value.isInitialized ||
                _isDisposed)
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 1 / _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
                const Positioned.fill(
                  child: CustomPaint(painter: OvalCutoutOverlayPainter()),
                ),
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOutOfRange
                              ? Colors.redAccent
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOutOfRange
                                ? Icons.location_off_rounded
                                : Icons.verified_user_rounded,
                            color: isOutOfRange
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _currentDistanceToStation != null
                                ? '${widget.station.name} (${_currentDistanceToStation!.toStringAsFixed(0)}m / max 100m)'
                                : '${widget.station.name} (100m Geofence)',
                            style: TextStyle(
                              color: isOutOfRange
                                  ? Colors.redAccent
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 36,
                  left: 28,
                  right: 28,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOutOfRange
                          ? Colors.grey.shade700
                          : (widget.isPunchIn
                                ? const Color(0xFF1E3A8A)
                                : const Color(0xFFD97706)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 6,
                    ),
                    onPressed: (_isProcessing || isOutOfRange)
                        ? null
                        : _performFacePunch,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.camera_front_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                    label: Text(
                      _isProcessing
                          ? 'Verifying Face & Location...'
                          : (isOutOfRange
                                ? 'Out of Range (>100m)'
                                : (widget.isPunchIn
                                      ? 'Punch In Now'
                                      : 'Punch Out Now')),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class OvalCutoutOverlayPainter extends CustomPainter {
  const OvalCutoutOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ovalWidth = size.width * 0.76;
    final ovalHeight = size.height * 0.52;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: ovalWidth,
      height: ovalHeight,
    );

    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(rect);

    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawOval(rect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
