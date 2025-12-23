import 'dart:math';
import 'dart:ui'; // Add this for Rect and Color
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Service to compare faces and determine similarity
class FaceComparatorService {
  /// Compare two faces and return similarity score (0.0 to 1.0)
  /// Higher score means more similar
  static double compareFaces(Face face1, Face face2) {
    double score = 0.0;
    int criteriaCount = 0;

    // 1. Compare bounding box size (face size similarity)
    final size1 = _getFaceSize(face1.boundingBox);
    final size2 = _getFaceSize(face2.boundingBox);
    final sizeRatio = min(size1, size2) / max(size1, size2);
    score += sizeRatio * 20; // 20% weight
    criteriaCount++;

    // 2. Compare head pose angles
    if (face1.headEulerAngleX != null && face2.headEulerAngleX != null) {
      final angleXDiff = (face1.headEulerAngleX! - face2.headEulerAngleX!).abs();
      final angleXScore = max(0.0, 1.0 - (angleXDiff / 90.0));
      score += angleXScore * 15; // 15% weight
      criteriaCount++;
    }

    if (face1.headEulerAngleY != null && face2.headEulerAngleY != null) {
      final angleYDiff = (face1.headEulerAngleY! - face2.headEulerAngleY!).abs();
      final angleYScore = max(0.0, 1.0 - (angleYDiff / 90.0));
      score += angleYScore * 15; // 15% weight
      criteriaCount++;
    }

    if (face1.headEulerAngleZ != null && face2.headEulerAngleZ != null) {
      final angleZDiff = (face1.headEulerAngleZ! - face2.headEulerAngleZ!).abs();
      final angleZScore = max(0.0, 1.0 - (angleZDiff / 90.0));
      score += angleZScore * 10; // 10% weight
      criteriaCount++;
    }

    // 3. Compare facial features probabilities
    if (face1.leftEyeOpenProbability != null && face2.leftEyeOpenProbability != null) {
      final eyeDiff = (face1.leftEyeOpenProbability! - face2.leftEyeOpenProbability!).abs();
      final eyeScore = 1.0 - eyeDiff;
      score += eyeScore * 10; // 10% weight
      criteriaCount++;
    }

    if (face1.rightEyeOpenProbability != null && face2.rightEyeOpenProbability != null) {
      final eyeDiff = (face1.rightEyeOpenProbability! - face2.rightEyeOpenProbability!).abs();
      final eyeScore = 1.0 - eyeDiff;
      score += eyeScore * 10; // 10% weight
      criteriaCount++;
    }

    if (face1.smilingProbability != null && face2.smilingProbability != null) {
      final smileDiff = (face1.smilingProbability! - face2.smilingProbability!).abs();
      final smileScore = 1.0 - smileDiff;
      score += smileScore * 10; // 10% weight
      criteriaCount++;
    }

    // 4. Compare bounding box aspect ratio (face shape)
    final ratio1 = _getFaceAspectRatio(face1.boundingBox);
    final ratio2 = _getFaceAspectRatio(face2.boundingBox);
    final ratioDiff = (ratio1 - ratio2).abs();
    final ratioScore = max(0.0, 1.0 - ratioDiff);
    score += ratioScore * 10; // 10% weight
    criteriaCount++;

    // Normalize score to 0-1 range
    return score / 100.0;
  }

  /// Compare a detected face against multiple registered faces
  /// Returns the best match score and whether it passes the threshold
  static MatchResult compareFaceAgainstRegistered({
    required Face detectedFace,
    required List<Face> registeredFaces,
    double threshold = 0.6, // 60% similarity threshold
  }) {
    double bestScore = 0.0;
    int bestMatchIndex = -1;

    for (int i = 0; i < registeredFaces.length; i++) {
      final score = compareFaces(detectedFace, registeredFaces[i]);
      if (score > bestScore) {
        bestScore = score;
        bestMatchIndex = i;
      }
    }

    final isMatch = bestScore >= threshold;
    final confidenceLevel = _getConfidenceLevel(bestScore);

    return MatchResult(
      isMatch: isMatch,
      score: bestScore,
      matchIndex: bestMatchIndex,
      confidenceLevel: confidenceLevel,
    );
  }

  /// Get face size (area)
  static double _getFaceSize(Rect boundingBox) {
    return boundingBox.width * boundingBox.height;
  }

  /// Get face aspect ratio (width/height)
  static double _getFaceAspectRatio(Rect boundingBox) {
    return boundingBox.width / boundingBox.height;
  }

  /// Get confidence level based on score
  static ConfidenceLevel _getConfidenceLevel(double score) {
    if (score >= 0.85) {
      return ConfidenceLevel.veryHigh;
    } else if (score >= 0.75) {
      return ConfidenceLevel.high;
    } else if (score >= 0.65) {
      return ConfidenceLevel.medium;
    } else if (score >= 0.55) {
      return ConfidenceLevel.low;
    } else {
      return ConfidenceLevel.veryLow;
    }
  }
}

/// Result of face matching
class MatchResult {
  final bool isMatch;
  final double score;
  final int matchIndex;
  final ConfidenceLevel confidenceLevel;

  MatchResult({
    required this.isMatch,
    required this.score,
    required this.matchIndex,
    required this.confidenceLevel,
  });

  String get scorePercentage => '${(score * 100).toStringAsFixed(1)}%';
}

/// Confidence level for face matching
enum ConfidenceLevel {
  veryHigh,
  high,
  medium,
  low,
  veryLow,
}

extension ConfidenceLevelExtension on ConfidenceLevel {
  String get displayName {
    switch (this) {
      case ConfidenceLevel.veryHigh:
        return 'Very High';
      case ConfidenceLevel.high:
        return 'High';
      case ConfidenceLevel.medium:
        return 'Medium';
      case ConfidenceLevel.low:
        return 'Low';
      case ConfidenceLevel.veryLow:
        return 'Very Low';
    }
  }

  Color get color {
    switch (this) {
      case ConfidenceLevel.veryHigh:
        return const Color(0xFF4CAF50); // Green
      case ConfidenceLevel.high:
        return const Color(0xFF8BC34A); // Light Green
      case ConfidenceLevel.medium:
        return const Color(0xFFFFC107); // Amber
      case ConfidenceLevel.low:
        return const Color(0xFFFF9800); // Orange
      case ConfidenceLevel.veryLow:
        return const Color(0xFFF44336); // Red
    }
  }
}