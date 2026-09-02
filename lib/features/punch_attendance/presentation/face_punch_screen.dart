import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:metro_shift_roster/core/services/face_biometric_service.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
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
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 3),
      );
      if (!_isDisposed) _preloadedPosition = fresh;
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
      if (user == null) throw Exception('Operator session expired.');

      Position? position =
          _preloadedPosition ?? await Geolocator.getLastKnownPosition();
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
      }

      if (position.isMocked) {
        throw Exception('Mock / Fake GPS detected! Punch rejected.');
      }

      final photo = await _cameraController!.takePicture();
      final liveEmbedding = await _faceService.extractFaceEmbeddingFromFile(
        photo.path,
      );

      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (liveEmbedding == null) {
        throw Exception(
          'No face detected. Align your face inside the green oval.',
        );
      }

      // Check registered face embedding with calibrated tolerance
      if (user.faceEmbedding != null && user.faceEmbedding!.isNotEmpty) {
        final similarity = _faceService.compareEmbeddings(
          liveEmbedding,
          user.faceEmbedding!,
        );

        if (similarity < 0.55) {
          throw Exception(
            'Face does not match registered profile! Please look straight at the camera.',
          );
        }
      }

      final res = await SupabaseService.client.rpc(
        'process_face_punch_record',
        params: {
          'p_session_id': widget.activeSessionId,
          'p_user_id': user.id,
          'p_org_id': user.orgId ?? '00000000-0000-0000-0000-000000000001',
          'p_station_id': widget.station.id,
          'p_is_punch_in': widget.isPunchIn,
          'p_face_embedding': liveEmbedding,
          'p_lat': position.latitude,
          'p_lng': position.longitude,
          'p_is_mocked': position.isMocked,
          'p_accuracy': position.accuracy,
        },
      );

      final data = res as Map<String, dynamic>;

      if (data['success'] == true) {
        ref.invalidate(activePunchSessionProvider);
        ref.invalidate(operatorSummaryMetricsProvider);
        ref.invalidate(punchAuditListProvider);

        if (mounted) {
          final isPresent = data['status'] == 'present';
          final msg = widget.isPunchIn
              ? 'Punch In Verified (${data['distance']}m) — ON DUTY'
              : (isPresent
                    ? 'Duty Completed! Marked PRESENT.'
                    : 'Incomplete Duty (<7h 50m). Marked ABSENT (₹0)');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: widget.isPunchIn || isPresent
                  ? const Color(0xFF059669)
                  : Colors.redAccent,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        throw Exception(data['error']?.toString() ?? 'Verification failed.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
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
    final isNotRegistered = user != null && !user.isFaceRegistered;

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
                      'Please register your face profile before performing punch in/out.',
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
                        'Go to Profile',
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
                // Camera Preview
                Center(
                  child: AspectRatio(
                    aspectRatio: 1 / _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                ),

                // Clear Cutout Oval Overlay: Dark Outside, 100% Clear Inside
                const Positioned.fill(
                  child: CustomPaint(painter: OvalCutoutOverlayPainter()),
                ),

                // Top Station Geofence Tag
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
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.station.name} (${widget.station.punchRadiusMeters}m Geofence)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom-Anchored Punch Button
                Positioned(
                  bottom: 36,
                  left: 28,
                  right: 28,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isPunchIn
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFFD97706),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 6,
                    ),
                    onPressed: _isProcessing ? null : _performFacePunch,
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
                          : (widget.isPunchIn
                                ? 'Punch In Now'
                                : 'Punch Out Now'),
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

/// Custom painter that tints the outside of the oval while keeping the inside crystal clear
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

    // Full screen background path
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // Cutout oval path
    final ovalPath = Path()..addOval(rect);

    // Combine paths to punch out the transparent center
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    // Green oval outline
    final strokePaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawOval(rect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
