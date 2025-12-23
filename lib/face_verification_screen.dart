import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'face_storage_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceVerificationScreen({super.key, required this.cameras});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  Face? _detectedFace;
  late CameraDescription _camera;

  List<Map<String, dynamic>>? _registeredFaceData;
  String? _registeredUserName;
  bool _isLoading = true;
  bool _hasRegisteredFace = false;

  bool _isVerifying = false;
  FaceMatchResult? _lastMatchResult;
  int _verificationAttempts = 0;
  static const int _maxAttempts = 3;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadRegisteredFaces();
  }

  Future<void> _loadRegisteredFaces() async {
    final faceData = await FaceStorageService.loadFaceData();
    final userName = await FaceStorageService.getUserName();

    setState(() {
      _registeredFaceData = faceData;
      _registeredUserName = userName ?? 'User';
      _hasRegisteredFace = faceData != null && faceData.isNotEmpty;
      _isLoading = false;
    });

    if (!_hasRegisteredFace) {
      _showNoRegistrationDialog();
    }
  }

  void _initializeCamera() {
    _camera = widget.cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(
      _camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );

    _controller.initialize().then((_) {
      if (mounted && _hasRegisteredFace) {
        _controller.startImageStream(_processImage);
        setState(() {});
      }
    });
  }

  void _processImage(CameraImage image) async {
    if (_isDetecting || _isVerifying || !_hasRegisteredFace) return;
    _isDetecting = true;

    final WriteBuffer buffer = WriteBuffer();
    for (Plane plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }

    final InputImageRotation rotation = _getImageRotation();

    final inputImage = InputImage.fromBytes(
      bytes: buffer.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );

    try {
      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _detectedFace = faces.isNotEmpty ? faces.first : null;
        });
      }
    } catch (e) {
      print('Error detecting faces: $e');
    }

    _isDetecting = false;
  }

  Future<void> _verifyFace() async {
    if (_detectedFace == null || _registeredFaceData == null) return;

    setState(() {
      _isVerifying = true;
      _verificationAttempts++;
    });

    print('🔍 STARTING VERIFICATION');
    print('   Comparing with ${_registeredFaceData!.length} registered samples');

    await Future.delayed(const Duration(milliseconds: 500));

    // Compare using facial geometry
    final similarityScore = FaceStorageService.compareFaces(
      _detectedFace!,
      _registeredFaceData!,
    );

    print('📊 SIMILARITY SCORE: ${(similarityScore * 100).toStringAsFixed(1)}%');

    // Threshold: 70% similarity required
    final threshold = 0.70;
    final isMatch = similarityScore >= threshold;
    final confidenceLevel = _getConfidenceLevel(similarityScore);

    final matchResult = FaceMatchResult(
      isMatch: isMatch,
      score: similarityScore,
      confidenceLevel: confidenceLevel,
    );

    setState(() {
      _lastMatchResult = matchResult;
      _isVerifying = false;
    });

    _showVerificationResultDialog(matchResult);
  }

  ConfidenceLevel _getConfidenceLevel(double score) {
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

  void _showVerificationResultDialog(FaceMatchResult result) {
    final isSuccess = result.isMatch;

    String failureReason = '';
    if (!isSuccess) {
      if (result.score < 0.50) {
        failureReason = 'Very low similarity. This appears to be a different person.';
      } else if (result.score < 0.65) {
        failureReason = 'Face does not match the registered user.';
      } else if (result.score < 0.70) {
        failureReason = 'Similarity too low for verification. Please ensure good lighting and position.';
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.cancel,
              color: isSuccess ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSuccess ? 'Verification Successful!' : 'Verification Failed',
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSuccess) ...[
              Text(
                'Welcome back, $_registeredUserName!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Identity confirmed!',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildResultRow('Similarity Score:', result.scorePercentage, result.confidenceLevel.color),
            const SizedBox(height: 8),
            _buildResultRow('Confidence:', result.confidenceLevel.displayName, result.confidenceLevel.color),
            const SizedBox(height: 8),
            _buildResultRow('Status:', isSuccess ? 'Verified ✓' : 'Not Verified ✗', isSuccess ? Colors.green : Colors.red),
            const SizedBox(height: 8),
            _buildResultRow('Threshold:', '≥70%', Colors.orange),
            if (!isSuccess) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.score >= 0.65 ? Colors.orange.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.score >= 0.65 ? Colors.orange.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          result.score >= 0.65 ? Icons.warning : Icons.error_outline,
                          color: result.score >= 0.65 ? Colors.orange : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.score >= 0.65 ? 'Insufficient Similarity' : 'Verification Failed',
                            style: TextStyle(
                              color: result.score >= 0.65 ? Colors.orange : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      failureReason,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_verificationAttempts < _maxAttempts) ...[
                const SizedBox(height: 8),
                Text(
                  'Attempts remaining: ${_maxAttempts - _verificationAttempts}/$_maxAttempts',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ],
          ],
        ),
        actions: [
          if (!isSuccess && _verificationAttempts < _maxAttempts)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _lastMatchResult = null;
                });
              },
              child: const Text('Try Again', style: TextStyle(fontSize: 16)),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (isSuccess || _verificationAttempts >= _maxAttempts) {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              isSuccess ? 'Done' : (_verificationAttempts >= _maxAttempts ? 'Exit' : 'Cancel'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showNoRegistrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 32),
            SizedBox(width: 10),
            Text('No Registered Face', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'You need to register your face first before you can verify.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  InputImageRotation _getImageRotation() {
    if (Platform.isAndroid) {
      return InputImageRotation.rotation270deg;
    } else {
      return InputImageRotation.rotation0deg;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_hasRegisteredFace) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final previewSize = _controller.value.previewSize!;
    final scale = screenSize.width / previewSize.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildInstructionBar(),
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: screenSize.width * 0.85,
                      height: screenSize.width * 0.85,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _getFrameColor(),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Transform.scale(
                          scale: scale,
                          child: Center(
                            child: CameraPreview(_controller),
                          ),
                        ),
                      ),
                    ),
                    if (_detectedFace != null)
                      CustomPaint(
                        size: Size(screenSize.width * 0.85, screenSize.width * 0.85),
                        painter: VerificationFaceOverlayPainter(
                          face: _detectedFace!,
                          imageSize: Size(
                            _controller.value.previewSize!.height,
                            _controller.value.previewSize!.width,
                          ),
                          containerSize: Size(
                            screenSize.width * 0.85,
                            screenSize.width * 0.85,
                          ),
                          matchResult: _lastMatchResult,
                        ),
                      ),
                    if (_isVerifying)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.blue),
                            SizedBox(height: 12),
                            Text(
                              'Verifying face...',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _buildVerifyButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.verified_user, color: Colors.blue, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Face Verification',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (_detectedFace == null)
            const Text(
              'Position your face in the frame',
              style: TextStyle(color: Colors.orange, fontSize: 14),
            )
          else
            const Text(
              'Face detected - Press verify',
              style: TextStyle(color: Colors.green, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    final canVerify = _detectedFace != null && !_isVerifying;

    return Container(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.fingerprint, size: 24),
          label: const Text(
            'Verify Face',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: canVerify ? Colors.blue : Colors.grey[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: canVerify ? 5 : 0,
          ),
          onPressed: canVerify ? _verifyFace : null,
        ),
      ),
    );
  }

  Color _getFrameColor() {
    if (_lastMatchResult != null) {
      return _lastMatchResult!.isMatch ? Colors.green : Colors.red;
    }
    if (_detectedFace != null) {
      return Colors.blue;
    }
    return Colors.grey;
  }
}

class VerificationFaceOverlayPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final Size containerSize;
  final FaceMatchResult? matchResult;

  VerificationFaceOverlayPainter({
    required this.face,
    required this.imageSize,
    required this.containerSize,
    this.matchResult,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Color color;
    if (matchResult != null) {
      color = matchResult!.isMatch ? Colors.green : Colors.red;
    } else {
      color = Colors.blue;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final Rect scaledRect = _scaleRect(face.boundingBox);
    canvas.drawRect(scaledRect, paint);
    _drawCorners(canvas, scaledRect, paint);
  }

  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    const double cornerLength = 25;
    final cornerPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    canvas.drawLine(rect.topLeft, Offset(rect.left + cornerLength, rect.top), cornerPaint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + cornerLength), cornerPaint);
    canvas.drawLine(rect.topRight, Offset(rect.right - cornerLength, rect.top), cornerPaint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + cornerLength), cornerPaint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left + cornerLength, rect.bottom), cornerPaint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left, rect.bottom - cornerLength), cornerPaint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right - cornerLength, rect.bottom), cornerPaint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - cornerLength), cornerPaint);
  }

  Rect _scaleRect(Rect rect) {
    final scaleX = containerSize.width / imageSize.width;
    final scaleY = containerSize.height / imageSize.height;

    double left = rect.left * scaleX;
    double top = rect.top * scaleY;
    double right = rect.right * scaleX;
    double bottom = rect.bottom * scaleY;

    final temp = left;
    left = containerSize.width - right;
    right = containerSize.width - temp;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant VerificationFaceOverlayPainter oldDelegate) {
    return oldDelegate.face != face || oldDelegate.matchResult != matchResult;
  }
}

class FaceMatchResult {
  final bool isMatch;
  final double score;
  final ConfidenceLevel confidenceLevel;

  FaceMatchResult({
    required this.isMatch,
    required this.score,
    required this.confidenceLevel,
  });

  String get scorePercentage => '${(score * 100).toStringAsFixed(1)}%';
}

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
        return const Color(0xFF4CAF50);
      case ConfidenceLevel.high:
        return const Color(0xFF8BC34A);
      case ConfidenceLevel.medium:
        return const Color(0xFFFFC107);
      case ConfidenceLevel.low:
        return const Color(0xFFFF9800);
      case ConfidenceLevel.veryLow:
        return const Color(0xFFF44336);
    }
  }
}