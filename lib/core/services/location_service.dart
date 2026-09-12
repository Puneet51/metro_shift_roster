import 'package:geolocator/geolocator.dart';

class LocationService {
  // In-memory cache so we never re-evaluate permission requests repeatedly.
  static bool _hasGrantedPermission = false;

  /// Check permissions once, remember it, and fetch current device coordinates
  static Future<Position> getCurrentCoordinates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled on this device. Please turn on GPS.',
      );
    }

    if (!_hasGrantedPermission) {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission was denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permissions are permanently denied. Please enable them in app settings.',
        );
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _hasGrantedPermission = true;
      }
    }

    // Attempt rapid high-accuracy location, fall back to last known position if device GPS is warm
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    }
  }

  /// Calculates geodesic distance between user and target station in meters
  static double calculateDistanceInMeters({
    required double userLat,
    required double userLng,
    required double targetLat,
    required double targetLng,
  }) {
    return Geolocator.distanceBetween(userLat, userLng, targetLat, targetLng);
  }
}
