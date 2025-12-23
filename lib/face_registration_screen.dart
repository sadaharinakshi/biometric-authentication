import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'face_storage_service.dart';

class RegistrationStep {
  final String instruction;
  final IconData icon;
  final bool Function(Face?) checkFunction;

  RegistrationStep({
    required this.instruction,
    required this.icon,
    required this.checkFunction,
  });
}

class FaceRegistrationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceRegistrationScreen({super.key, required this.cameras});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  Face? _detectedFace;
  late CameraDescription _camera;

  int _currentStep = 0;
  late List<RegistrationStep> _steps;

  bool _stepCompleted = false;
  int _holdCounter = 0;
  static const int _holdDuration = 30;

  List<Face> _capturedFaces = []; // Just store Face objects
  bool _isRegistrationComplete = false;
  String _userName = '';

  @override
  void initState() {
    super.initState();

    _steps = [
      RegistrationStep(
        instruction: "Look straight at the camera",
        icon: Icons.face,
        checkFunction: _checkFacingForward,
      ),
      RegistrationStep(
        instruction: "Turn your head LEFT",
        icon: Icons.arrow_back,
        checkFunction: _checkTurnLeft,
      ),
      RegistrationStep(
        instruction: "Turn your head RIGHT",
        icon: Icons.arrow_forward,
        checkFunction: _checkTurnRight,
      ),
    ];

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
        enableContours: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.2,
      ),
    );

    _controller.initialize().then((_) {
      _controller.startImageStream(_processImage);
      setState(() {});
    });
  }

  void _processImage(CameraImage image) async {
    if (_isDetecting || _isRegistrationComplete) return;
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

      if (mounted && !_isRegistrationComplete) {
        setState(() {
          _detectedFace = faces.isNotEmpty ? faces.first : null;
        });

        if (_detectedFace != null && !_stepCompleted) {
          bool stepSatisfied = _steps[_currentStep].checkFunction(_detectedFace);

          if (stepSatisfied) {
            _holdCounter++;
            if (_holdCounter >= _holdDuration) {
              _captureCurrentFace(_detectedFace!);
              _moveToNextStep();
            }
          } else {
            _holdCounter = 0;
          }
        }
      }
    } catch (e) {
      print('Error detecting faces: $e');
    }

    _isDetecting = false;
  }

  void _captureCurrentFace(Face face) {
    _capturedFaces.add(face);
    print('✅ Captured face ${_capturedFaces.length}: ${_steps[_currentStep].instruction}');
  }

  void _moveToNextStep() {
    setState(() {
      _holdCounter = 0;
      _stepCompleted = true;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          if (_currentStep < _steps.length - 1) {
            _currentStep++;
            _stepCompleted = false;
          } else {
            _completeRegistration();
          }
        });
      }
    });
  }

  void _completeRegistration() {
    setState(() {
      _isRegistrationComplete = true;
    });

    _controller.stopImageStream();
    _showNameInputDialog();
  }

  void _showNameInputDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person, color: Colors.blue, size: 32),
            SizedBox(width: 10),
            Text('Enter Your Name', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please enter your name to complete registration.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter name',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                _userName = value;
              },
              onSubmitted: (_) {
                if (_userName.isNotEmpty) {
                  _saveFaceDataAndShowSuccess();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_userName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a name'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } else {
                Navigator.of(context).pop();
                _saveFaceDataAndShowSuccess();
              }
            },
            child: const Text('Continue', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFaceDataAndShowSuccess() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Saving face data...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final success = await FaceStorageService.saveFaceData(
      faces: _capturedFaces,
      userName: _userName,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }

    if (success) {
      _showRegistrationCompleteDialog();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save face data. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRegistrationCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 10),
            Text('Registration Complete!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $_userName!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your face has been successfully registered.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Captured ${_capturedFaces.length} face samples',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can now use face verification!',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done', style: TextStyle(fontSize: 16)),
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

  static bool _checkFacingForward(Face? face) {
    if (face == null) return false;
    final headY = face.headEulerAngleY ?? 0;
    final headX = face.headEulerAngleX ?? 0;
    return headY.abs() < 15 && headX.abs() < 15;
  }

  static bool _checkTurnLeft(Face? face) {
    if (face == null) return false;
    final headY = face.headEulerAngleY ?? 0;
    return headY > 25 && headY < 50;
  }

  static bool _checkTurnRight(Face? face) {
    if (face == null) return false;
    final headY = face.headEulerAngleY ?? 0;
    return headY < -25 && headY > -50;
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
                          color: _getStepColor(),
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
                        painter: FaceOverlayPainter(
                          face: _detectedFace!,
                          imageSize: Size(
                            _controller.value.previewSize!.height,
                            _controller.value.previewSize!.width,
                          ),
                          containerSize: Size(
                            screenSize.width * 0.85,
                            screenSize.width * 0.85,
                          ),
                          isValid: _steps[_currentStep].checkFunction(_detectedFace),
                        ),
                      ),
                    if (_holdCounter > 0 && !_stepCompleted)
                      _buildProgressIndicator(),
                  ],
                ),
              ),
            ),
            _buildBottomProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getStepColor().withOpacity(0.3),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Step ${_currentStep + 1} of ${_steps.length}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            _steps[_currentStep].icon,
            color: _getStepColor(),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _steps[_currentStep].instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
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
          else if (!_steps[_currentStep].checkFunction(_detectedFace))
            const Text(
              'Follow the instruction above',
              style: TextStyle(color: Colors.orange, fontSize: 14),
            )
          else if (!_stepCompleted)
              const Text(
                'Hold still...',
                style: TextStyle(color: Colors.green, fontSize: 14),
              )
            else
              const Text(
                '✓ Step completed!',
                style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
              ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final progress = _holdCounter / _holdDuration;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(_getStepColor()),
            ),
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomProgress() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_steps.length, (index) {
          bool isCompleted = index < _currentStep;
          bool isCurrent = index == _currentStep;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: isCurrent ? 40 : 30,
            height: 30,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isCurrent ? _getStepColor() : Colors.grey[800]),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text(
                '${index + 1}',
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Color _getStepColor() {
    if (_stepCompleted) return Colors.green;
    if (_holdCounter > 0) return Colors.green;
    return Colors.blue;
  }
}

class FaceOverlayPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final Size containerSize;
  final bool isValid;

  FaceOverlayPainter({
    required this.face,
    required this.imageSize,
    required this.containerSize,
    required this.isValid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isValid ? Colors.green : Colors.orange
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
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.face != face || oldDelegate.isValid != isValid;
  }
}