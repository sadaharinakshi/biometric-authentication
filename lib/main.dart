import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'face_registration_screen.dart';
import 'face_verification_screen.dart';
import 'face_storage_service.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasFaceRegistered = false;
  String? _registeredUserName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkRegistrationStatus();
  }

  Future<void> _checkRegistrationStatus() async {
    final hasRegistered = await FaceStorageService.hasFaceRegistered();
    final userName = await FaceStorageService.getUserName();

    setState(() {
      _hasFaceRegistered = hasRegistered;
      _registeredUserName = userName;
      _isLoading = false;
    });
  }

  Future<void> _clearRegistration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 32),
            SizedBox(width: 10),
            Text('Clear Registration?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Are you sure you want to clear the registered face data? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await FaceStorageService.clearFaceData();
      if (success && mounted) {
        setState(() {
          _hasFaceRegistered = false;
          _registeredUserName = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face registration cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text("Face Recognition System"),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_hasFaceRegistered)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                _showSettingsDialog();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Icon/Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.face,
                  size: 80,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 40),

              // Title
              const Text(
                "Welcome",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle with user info
              if (_hasFaceRegistered && _registeredUserName != null) ...[
                Text(
                  _registeredUserName!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Text(
                "Secure face recognition system",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),

              // Registration status indicator
              if (_hasFaceRegistered) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Face Registered',
                        style: TextStyle(color: Colors.green, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 60),

              // Register Face Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: Icon(
                    _hasFaceRegistered ? Icons.replay : Icons.person_add,
                    size: 24,
                  ),
                  label: Text(
                    _hasFaceRegistered ? "Re-register Face" : "Register New Face",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasFaceRegistered ? Colors.orange : Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  onPressed: () async {
                    if (_hasFaceRegistered) {
                      // Show warning that face is already registered
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.orange, size: 32),
                              SizedBox(width: 10),
                              Text('Already Registered', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                          content: const Text(
                            'You have already registered your face. To register again, you must first clear your current registration from Settings.',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _showSettingsDialog();
                              },
                              child: const Text('Go to Settings', style: TextStyle(fontSize: 16)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FaceRegistrationScreen(cameras: cameras),
                      ),
                    );

                    // Refresh status after registration
                    if (result != null || mounted) {
                      _checkRegistrationStatus();
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Verify Face Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.verified_user, size: 24),
                  label: const Text(
                    "Verify Face",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasFaceRegistered ? Colors.green : Colors.grey[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: _hasFaceRegistered ? 5 : 0,
                  ),
                  onPressed: () async {
                    if (!_hasFaceRegistered) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please register your face first!"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FaceVerificationScreen(cameras: cameras),
                      ),
                    );

                    // You can handle verification result here if needed
                    if (result != null) {
                      print('Verification result: $result');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blue, size: 32),
            SizedBox(width: 10),
            Text('Settings', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text('Registered User', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _registeredUserName ?? 'Unknown',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Clear Registration', style: TextStyle(color: Colors.red)),
              subtitle: Text(
                'Remove saved face data',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _clearRegistration();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}