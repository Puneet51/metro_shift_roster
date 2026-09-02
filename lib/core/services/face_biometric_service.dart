import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceBiometricService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableContours: true,
      enableClassification: false,
      minFaceSize: 0.15,
    ),
  );

  /// Extracts 192-d normalized biometric vector from image
  Future<List<double>?> extractFaceEmbeddingFromFile(String filePath) async {
    try {
      final inputImage = InputImage.fromFile(File(filePath));
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) return null;
      return _generateVectorFromFace(faces.first);
    } catch (_) {
      return null;
    }
  }

  /// Compares live and registered face embeddings.
  /// Returns a similarity score between 0.0 and 1.0.
  double compareEmbeddings(dynamic liveEmbedding, dynamic registeredEmbedding) {
    try {
      List<double> v1 = _parseEmbeddingList(liveEmbedding);
      List<double> v2 = _parseEmbeddingList(registeredEmbedding);

      if (v1.isEmpty || v2.isEmpty) return 0.0;

      // Adjust length match
      final len = min(v1.length, v2.length);
      if (len < 16) return 0.0;

      double dot = 0.0;
      double mag1 = 0.0;
      double mag2 = 0.0;

      for (int i = 0; i < len; i++) {
        dot += v1[i] * v2[i];
        mag1 += v1[i] * v1[i];
        mag2 += v2[i] * v2[i];
      }

      mag1 = sqrt(mag1);
      mag2 = sqrt(mag2);

      if (mag1 == 0.0 || mag2 == 0.0) return 0.0;
      final similarity = dot / (mag1 * mag2);

      // Clamp to range [0.0, 1.0]
      return similarity.clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  List<double> _parseEmbeddingList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List<double>) return raw;
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => (e as num).toDouble()).toList();
        }
        if (decoded is Map && decoded['embedding'] != null) {
          final emb = decoded['embedding'];
          if (emb is List) {
            return emb.map((e) => (e as num).toDouble()).toList();
          }
        }
      } catch (_) {
        return raw
            .replaceAll('[', '')
            .replaceAll(']', '')
            .split(',')
            .map((s) => double.tryParse(s.trim()) ?? 0.0)
            .toList();
      }
    }
    return [];
  }

  List<double> _generateVectorFromFace(Face face) {
    final List<double> vector = [];
    final box = face.boundingBox;

    // Normalize coordinates relative to bounding box center to eliminate distance scaling
    final centerX = box.left + box.width / 2.0;
    final centerY = box.top + box.height / 2.0;
    final scale = max(box.width, box.height).toDouble();

    void addPoint(Point<int>? pt) {
      if (pt != null && scale > 0) {
        vector.add((pt.x - centerX) / scale);
        vector.add((pt.y - centerY) / scale);
      } else {
        vector.add(0.0);
        vector.add(0.0);
      }
    }

    addPoint(face.landmarks[FaceLandmarkType.leftEye]?.position);
    addPoint(face.landmarks[FaceLandmarkType.rightEye]?.position);
    addPoint(face.landmarks[FaceLandmarkType.noseBase]?.position);
    addPoint(face.landmarks[FaceLandmarkType.leftMouth]?.position);
    addPoint(face.landmarks[FaceLandmarkType.rightMouth]?.position);
    addPoint(face.landmarks[FaceLandmarkType.bottomMouth]?.position);

    face.contours.forEach((_, contour) {
      if (contour != null && contour.points.isNotEmpty) {
        for (int i = 0; i < min(4, contour.points.length); i++) {
          final pt = contour.points[i];
          if (scale > 0) {
            vector.add((pt.x - centerX) / scale);
            vector.add((pt.y - centerY) / scale);
          }
        }
      }
    });

    while (vector.length < 192) {
      vector.add(sin(vector.length * 0.17) * 0.05);
    }
    if (vector.length > 192) {
      vector.removeRange(192, vector.length);
    }

    // Unit vector normalization
    double norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] = vector[i] / norm;
      }
    }

    return vector;
  }

  void dispose() {
    _detector.close();
  }
}
