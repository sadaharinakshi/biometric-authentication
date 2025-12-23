import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';

class FaceCamera extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceCamera({super.key, required this.cameras});

  @override
  State<FaceCamera> createState() => _FaceCameraState();
}

class _FaceCameraState extends State<FaceCamera> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  List<Face> _faces = [];
  late CameraDescription _camera;

  @override
  void initState() {
    super.initState();

    _camera = widget.cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(
      _camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _controller.initialize().then((_) {
      _controller.startImageStream(_processImage);
      setState(() {});
    });
  }

  void _processImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    final WriteBuffer buffer = WriteBuffer();
    for (Plane plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }

    // Get the correct rotation for the device
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
        setState(() => _faces = faces);
      }
    } catch (e) {
      print('Error detecting faces: $e');
    }

    _isDetecting = false;
  }

  // Get the correct rotation based on device orientation
  InputImageRotation _getImageRotation() {
    // For Android, sensor orientation needs adjustment
    if (Platform.isAndroid) {
      // Front camera on Android typically needs 270 degrees rotation
      return InputImageRotation.rotation270deg;
    } else {
      // iOS typically works with 0 or 90 degrees
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
    if (!_controller.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Face Detection"),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          CameraPreview(_controller),

          // Face Detection Overlay
          CustomPaint(
            painter: FacePainter(
              faces: _faces,
              imageSize: Size(
                _controller.value.previewSize!.height,
                _controller.value.previewSize!.width,
              ),
              rotation: _controller.description.sensorOrientation,
              cameraLensDirection: _controller.description.lensDirection,
            ),
          ),

          // Debug Info (optional - remove in production)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Faces: ${_faces.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    'Preview: ${_controller.value.previewSize?.width.toInt()}x${_controller.value.previewSize?.height.toInt()}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    'Orientation: ${_controller.description.sensorOrientation}°',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final int rotation;
  final CameraLensDirection cameraLensDirection;

  FacePainter({
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final textPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    for (Face face in faces) {
      // Transform the bounding box coordinates
      final Rect scaledRect = _scaleRect(
        rect: face.boundingBox,
        imageSize: imageSize,
        widgetSize: size,
        rotation: rotation,
        cameraLensDirection: cameraLensDirection,
      );

      // Draw the face bounding box
      canvas.drawRect(scaledRect, paint);

      // Draw corner markers for better visibility
      _drawCorners(canvas, scaledRect, paint);

      // Draw eye open probability if available
      if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
        final textSpan = TextSpan(
          text: 'L: ${(face.leftEyeOpenProbability! * 100).toInt()}% '
              'R: ${(face.rightEyeOpenProbability! * 100).toInt()}%',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 14,
            backgroundColor: Colors.black54,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(scaledRect.left, scaledRect.top - 20),
        );
      }
    }
  }

  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    const double cornerLength = 30;
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    // Top-left corner
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left + cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left, rect.top + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right - cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right, rect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - cornerLength),
      cornerPaint,
    );
  }

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
    required int rotation,
    required CameraLensDirection cameraLensDirection,
  }) {
    // Calculate scale factors
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    // Scale the rectangle
    double left = rect.left * scaleX;
    double top = rect.top * scaleY;
    double right = rect.right * scaleX;
    double bottom = rect.bottom * scaleY;

    // Handle front camera mirroring
    if (cameraLensDirection == CameraLensDirection.front) {
      // Mirror horizontally for front camera
      final double temp = left;
      left = widgetSize.width - right;
      right = widgetSize.width - temp;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}