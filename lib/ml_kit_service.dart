import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Service to extract face embeddings using ML Kit landmarks
/// This provides a much more accurate face comparison than geometric features alone
class MLKitService {
  /// Extract face embedding (feature vector) from a face
  /// This creates a normalized representation of facial features
  static List<double> extractFaceEmbedding(Face face, img.Image image) {
    List<double> embedding = [];

    // 1. Extract normalized landmark positions (relative to face bounding box)
    final landmarks = face.landmarks;
    final boundingBox = face.boundingBox;

    // Key landmarks for face identity
    final keyLandmarkTypes = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
    ];

    // Normalize landmark positions relative to face center
    final faceCenterX = boundingBox.left + boundingBox.width / 2;
    final faceCenterY = boundingBox.top + boundingBox.height / 2;
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;

    for (final type in keyLandmarkTypes) {
      final landmark = landmarks[type];
      if (landmark != null && landmark.position != null) {
        // Normalize to [-1, 1] range relative to face center
        final normalizedX = (landmark.position.x - faceCenterX) / (faceWidth / 2);
        final normalizedY = (landmark.position.y - faceCenterY) / (faceHeight / 2);
        embedding.add(normalizedX);
        embedding.add(normalizedY);
      } else {
        // Use zeros for missing landmarks
        embedding.add(0.0);
        embedding.add(0.0);
      }
    }

    // 2. Calculate inter-landmark distances (facial geometry)
    // These are pose-invariant features
    if (landmarks[FaceLandmarkType.leftEye] != null &&
        landmarks[FaceLandmarkType.rightEye] != null) {
      final eyeDistance = _calculateDistance(
        landmarks[FaceLandmarkType.leftEye]!.position,
        landmarks[FaceLandmarkType.rightEye]!.position,
      );
      // Normalize by face width
      embedding.add(eyeDistance / faceWidth);
    } else {
      embedding.add(0.0);
    }

    if (landmarks[FaceLandmarkType.noseBase] != null &&
        landmarks[FaceLandmarkType.leftEye] != null) {
      final noseToEyeDistance = _calculateDistance(
        landmarks[FaceLandmarkType.noseBase]!.position,
        landmarks[FaceLandmarkType.leftEye]!.position,
      );
      embedding.add(noseToEyeDistance / faceHeight);
    } else {
      embedding.add(0.0);
    }

    if (landmarks[FaceLandmarkType.leftMouth] != null &&
        landmarks[FaceLandmarkType.rightMouth] != null) {
      final mouthWidth = _calculateDistance(
        landmarks[FaceLandmarkType.leftMouth]!.position,
        landmarks[FaceLandmarkType.rightMouth]!.position,
      );
      embedding.add(mouthWidth / faceWidth);
    } else {
      embedding.add(0.0);
    }

    // 3. Face aspect ratio
    embedding.add(faceWidth / faceHeight);

    // 4. Extract pixel intensity features from key facial regions
    // This helps capture texture and appearance information
    final faceRegionFeatures = _extractFaceRegionFeatures(image, face);
    embedding.addAll(faceRegionFeatures);

    // 5. Add facial expression features (normalized)
    if (face.smilingProbability != null) {
      embedding.add(face.smilingProbability!);
    } else {
      embedding.add(0.5);
    }

    if (face.leftEyeOpenProbability != null) {
      embedding.add(face.leftEyeOpenProbability!);
    } else {
      embedding.add(0.5);
    }

    if (face.rightEyeOpenProbability != null) {
      embedding.add(face.rightEyeOpenProbability!);
    } else {
      embedding.add(0.5);
    }

    return embedding;
  }

  /// Extract features from key facial regions
  static List<double> _extractFaceRegionFeatures(img.Image image, Face face) {
    List<double> features = [];
    final boundingBox = face.boundingBox;

    // Define regions: eyes, nose, mouth areas
    final regions = [
      // Left eye region
      Rect.fromLTRB(
        boundingBox.left + boundingBox.width * 0.15,
        boundingBox.top + boundingBox.height * 0.25,
        boundingBox.left + boundingBox.width * 0.4,
        boundingBox.top + boundingBox.height * 0.4,
      ),
      // Right eye region
      Rect.fromLTRB(
        boundingBox.left + boundingBox.width * 0.6,
        boundingBox.top + boundingBox.height * 0.25,
        boundingBox.left + boundingBox.width * 0.85,
        boundingBox.top + boundingBox.height * 0.4,
      ),
      // Nose region
      Rect.fromLTRB(
        boundingBox.left + boundingBox.width * 0.35,
        boundingBox.top + boundingBox.height * 0.4,
        boundingBox.left + boundingBox.width * 0.65,
        boundingBox.top + boundingBox.height * 0.65,
      ),
      // Mouth region
      Rect.fromLTRB(
        boundingBox.left + boundingBox.width * 0.3,
        boundingBox.top + boundingBox.height * 0.65,
        boundingBox.left + boundingBox.width * 0.7,
        boundingBox.top + boundingBox.height * 0.85,
      ),
    ];

    for (final region in regions) {
      features.add(_calculateRegionBrightness(image, region));
      features.add(_calculateRegionContrast(image, region));
    }

    return features;
  }

  /// Calculate average brightness of a region
  static double _calculateRegionBrightness(img.Image image, Rect region) {
    int totalBrightness = 0;
    int pixelCount = 0;

    final x1 = max(0, region.left.toInt());
    final y1 = max(0, region.top.toInt());
    final x2 = min(image.width - 1, region.right.toInt());
    final y2 = min(image.height - 1, region.bottom.toInt());

    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        final pixel = image.getPixel(x, y);
        // Calculate luminance
        final brightness = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).toInt();
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    return pixelCount > 0 ? totalBrightness / (pixelCount * 255.0) : 0.5;
  }

  /// Calculate contrast (standard deviation) of a region
  static double _calculateRegionContrast(img.Image image, Rect region) {
    List<double> brightnesses = [];

    final x1 = max(0, region.left.toInt());
    final y1 = max(0, region.top.toInt());
    final x2 = min(image.width - 1, region.right.toInt());
    final y2 = min(image.height - 1, region.bottom.toInt());

    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114) / 255.0;
        brightnesses.add(brightness);
      }
    }

    if (brightnesses.isEmpty) return 0.0;

    final mean = brightnesses.reduce((a, b) => a + b) / brightnesses.length;
    final variance = brightnesses.map((b) => pow(b - mean, 2)).reduce((a, b) => a + b) / brightnesses.length;
    return sqrt(variance);
  }

  /// Calculate Euclidean distance between two points
  static double _calculateDistance(Point<int> p1, Point<int> p2) {
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Compare two face embeddings using cosine similarity
  /// Returns similarity score from 0.0 to 1.0 (higher is more similar)
  static double compareEmbeddings(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      print('⚠️ Warning: Embeddings have different lengths');
      return 0.0;
    }

    // Calculate cosine similarity
    double dotProduct = 0.0;
    double magnitude1 = 0.0;
    double magnitude2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      magnitude1 += embedding1[i] * embedding1[i];
      magnitude2 += embedding2[i] * embedding2[i];
    }

    magnitude1 = sqrt(magnitude1);
    magnitude2 = sqrt(magnitude2);

    if (magnitude1 == 0.0 || magnitude2 == 0.0) {
      return 0.0;
    }

    // Cosine similarity ranges from -1 to 1, normalize to 0 to 1
    final cosineSimilarity = dotProduct / (magnitude1 * magnitude2);
    final normalizedSimilarity = (cosineSimilarity + 1.0) / 2.0;

    return normalizedSimilarity;
  }

  /// Compare multiple embeddings and return the best match
  static double compareFaceEmbeddings(
      List<double> detectedEmbedding,
      List<List<double>> registeredEmbeddings,
      ) {
    if (registeredEmbeddings.isEmpty) return 0.0;

    double bestScore = 0.0;

    for (final registeredEmbedding in registeredEmbeddings) {
      final score = compareEmbeddings(detectedEmbedding, registeredEmbedding);
      if (score > bestScore) {
        bestScore = score;
      }
    }

    return bestScore;
  }

  /// Convert camera image bytes to img.Image
  static img.Image? convertYUV420ToImage(Uint8List bytes, int width, int height) {
    try {
      // Create image from YUV420 format
      final image = img.Image(width: width, height: height);

      final int uvRowStride = width;
      final int uvPixelStride = 1;

      int yIndex = 0;
      int uvIndex = width * height;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yValue = bytes[yIndex++] & 0xFF;

          final int uvOffset = uvIndex + (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          final int uValue = (bytes[uvOffset] & 0xFF) - 128;
          final int vValue = (bytes[uvOffset + 1] & 0xFF) - 128;

          // YUV to RGB conversion
          int r = (yValue + 1.370705 * vValue).round().clamp(0, 255);
          int g = (yValue - 0.337633 * uValue - 0.698001 * vValue).round().clamp(0, 255);
          int b = (yValue + 1.732446 * uValue).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return image;
    } catch (e) {
      print('Error converting YUV420 to Image: $e');
      return null;
    }
  }
}

/// Rect extension for easier manipulation
extension RectExtension on Rect {
  Rect clamp(int maxWidth, int maxHeight) {
    return Rect.fromLTRB(
      left.clamp(0.0, maxWidth.toDouble()),
      top.clamp(0.0, maxHeight.toDouble()),
      right.clamp(0.0, maxWidth.toDouble()),
      bottom.clamp(0.0, maxHeight.toDouble()),
    );
  }
}