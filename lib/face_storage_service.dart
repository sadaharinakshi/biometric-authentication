import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Simple and reliable face storage using just landmark data
class FaceStorageService {
  static const String _keyFaceData = 'face_landmark_data';
  static const String _keyUserName = 'user_name';

  /// Save face landmark data
  static Future<bool> saveFaceData({
    required List<Face> faces,
    required String userName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Extract and save landmark data from faces
      final List<Map<String, dynamic>> faceDataList = faces.map((face) {
        return _extractFaceFeatures(face);
      }).toList();

      await prefs.setString(_keyFaceData, jsonEncode(faceDataList));
      await prefs.setString(_keyUserName, userName);

      print('✅ Saved ${faces.length} face samples for $userName');
      return true;
    } catch (e) {
      print('❌ Error saving face data: $e');
      return false;
    }
  }

  /// Load saved face data
  static Future<List<Map<String, dynamic>>?> loadFaceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_keyFaceData);

      if (data == null) {
        print('ℹ️ No face data found');
        return null;
      }

      final List<dynamic> jsonList = jsonDecode(data);
      final result = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      print('✅ Loaded ${result.length} face samples');
      return result;
    } catch (e) {
      print('❌ Error loading face data: $e');
      return null;
    }
  }

  /// Get registered user name
  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName);
  }

  /// Check if face is registered
  static Future<bool> hasFaceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyFaceData);
  }

  /// Clear all face data
  static Future<bool> clearFaceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFaceData);
      await prefs.remove(_keyUserName);
      print('✅ Face data cleared');
      return true;
    } catch (e) {
      print('❌ Error clearing face data: $e');
      return false;
    }
  }

  /// Compare detected face with registered faces - PUBLIC METHOD
  static double compareFaces(Face detectedFace, List<Map<String, dynamic>> registeredData) {
    final detectedFeatures = _extractFaceFeatures(detectedFace);

    print('🔍 Comparing detected face with ${registeredData.length} registered samples');

    double bestScore = 0.0;

    for (int i = 0; i < registeredData.length; i++) {
      final score = _compareFaceFeatures(detectedFeatures, registeredData[i]);
      print('   Sample ${i + 1}: ${(score * 100).toStringAsFixed(1)}%');
      if (score > bestScore) {
        bestScore = score;
      }
    }

    print('   Best match: ${(bestScore * 100).toStringAsFixed(1)}%');
    return bestScore;
  }

  /// Extract key features from face for comparison - PRIVATE
  static Map<String, dynamic> _extractFaceFeatures(Face face) {
    Map<String, dynamic> features = {};

    // Save bounding box (normalized)
    features['boundingBox'] = {
      'width': face.boundingBox.width,
      'height': face.boundingBox.height,
      'aspectRatio': face.boundingBox.width / face.boundingBox.height,
    };

    // Save head angles
    features['headAngles'] = {
      'x': face.headEulerAngleX ?? 0.0,
      'y': face.headEulerAngleY ?? 0.0,
      'z': face.headEulerAngleZ ?? 0.0,
    };

    // Save landmarks (relative positions)
    Map<String, Map<String, double>> landmarks = {};
    face.landmarks.forEach((type, landmark) {
      if (landmark != null) {
        // Normalize landmark position relative to face bounding box
        landmarks[type.name] = {
          'x': (landmark.position.x - face.boundingBox.left) / face.boundingBox.width,
          'y': (landmark.position.y - face.boundingBox.top) / face.boundingBox.height,
        };
      }
    });
    features['landmarks'] = landmarks;

    // Calculate inter-landmark distances (these are very stable)
    final distances = _calculateLandmarkDistances(face);
    features['distances'] = distances;

    return features;
  }

  /// Calculate distances between key landmarks (facial geometry) - PRIVATE
  static Map<String, double> _calculateLandmarkDistances(Face face) {
    Map<String, double> distances = {};

    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    final noseBase = face.landmarks[FaceLandmarkType.noseBase];
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];

    // Eye distance (very stable feature)
    if (leftEye != null && rightEye != null) {
      distances['eyeDistance'] = _distance(leftEye.position, rightEye.position);
    }

    // Nose to eyes
    if (noseBase != null && leftEye != null) {
      distances['noseToLeftEye'] = _distance(noseBase.position, leftEye.position);
    }
    if (noseBase != null && rightEye != null) {
      distances['noseToRightEye'] = _distance(noseBase.position, rightEye.position);
    }

    // Mouth width
    if (leftMouth != null && rightMouth != null) {
      distances['mouthWidth'] = _distance(leftMouth.position, rightMouth.position);
    }

    // Nose to mouth
    if (noseBase != null && leftMouth != null) {
      distances['noseToMouth'] = _distance(noseBase.position, leftMouth.position);
    }

    // Normalize all distances by face width
    final faceWidth = distances['eyeDistance'] ?? 100.0;
    distances.updateAll((key, value) => value / faceWidth);

    return distances;
  }

  /// Calculate Euclidean distance between two points - PRIVATE
  static double _distance(Point<int> p1, Point<int> p2) {
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Compare two face feature maps - PRIVATE
  static double _compareFaceFeatures(Map<String, dynamic> face1, Map<String, dynamic> face2) {
    double totalScore = 0.0;
    int componentCount = 0;

    // 1. Compare facial geometry (distances) - 50% weight
    final distances1 = face1['distances'] as Map<String, dynamic>;
    final distances2 = face2['distances'] as Map<String, dynamic>;

    double distanceScore = 0.0;
    int distanceCount = 0;

    distances1.forEach((key, value1) {
      if (distances2.containsKey(key)) {
        final value2 = distances2[key] as double;
        // Calculate similarity (1 - normalized difference)
        final diff = (value1 - value2).abs();
        final similarity = max(0.0, 1.0 - (diff * 5)); // Scale difference
        distanceScore += similarity;
        distanceCount++;
      }
    });

    if (distanceCount > 0) {
      totalScore += (distanceScore / distanceCount) * 50.0;
      componentCount++;
    }

    // 2. Compare aspect ratio - 20% weight
    final ratio1 = face1['boundingBox']['aspectRatio'] as double;
    final ratio2 = face2['boundingBox']['aspectRatio'] as double;
    final ratioDiff = (ratio1 - ratio2).abs();
    final ratioScore = max(0.0, 1.0 - (ratioDiff * 2));
    totalScore += ratioScore * 20.0;
    componentCount++;

    // 3. Compare landmark positions - 30% weight
    final landmarks1 = face1['landmarks'] as Map<String, dynamic>;
    final landmarks2 = face2['landmarks'] as Map<String, dynamic>;

    double landmarkScore = 0.0;
    int landmarkCount = 0;

    landmarks1.forEach((key, value1) {
      if (landmarks2.containsKey(key)) {
        final pos1 = value1 as Map<String, dynamic>;
        final pos2 = landmarks2[key] as Map<String, dynamic>;

        final dx = (pos1['x'] as double) - (pos2['x'] as double);
        final dy = (pos1['y'] as double) - (pos2['y'] as double);
        final distance = sqrt(dx * dx + dy * dy);

        // Similarity decreases with distance
        final similarity = max(0.0, 1.0 - (distance * 3));
        landmarkScore += similarity;
        landmarkCount++;
      }
    });

    if (landmarkCount > 0) {
      totalScore += (landmarkScore / landmarkCount) * 30.0;
      componentCount++;
    }

    return totalScore / 100.0; // Return score between 0 and 1
  }
}