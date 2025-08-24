import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const VideoApp());
}

class VideoApp extends StatelessWidget {
  const VideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Overlay Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isRecording = false;
  int _selectedCameraIndex = 0;
  bool _isPaused = false;
  String? _overlayPath;
  XFile? _videoFile;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _initCamera(int cameraIndex) async {
    await _controller?.dispose();
    _controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );
    _initializeControllerFuture = _controller!.initialize();
    await _initializeControllerFuture;
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.isRecordingVideo) {
      try {
        final file = await _controller!.stopVideoRecording();
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String videoPath = '${appDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final File videoFile = await File(file.path).copy(videoPath);

        setState(() {
          _isRecording = false;
          _videoFile = XFile(videoFile.path);
        });

        print("Video saved to: ${videoFile.path}");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Video recorded! Tap save to add to gallery.")),
          );
        }
      } catch (e) {
        print("Stop recording error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Recording error: $e")),
          );
        }
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _videoFile = null;
        });
      } catch (e) {
        print("Start recording error: $e");
      }
    }
  }

  void _switchCamera() {
    if (cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    _initCamera(_selectedCameraIndex);
  }

  void _togglePause() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (!_isPaused) {
      try {
        final image = await _controller!.takePicture();
        setState(() {
          _isPaused = true;
          _overlayPath = image.path;
        });
      } catch (e) {
        print("Error taking snapshot: $e");
      }
    } else {
      setState(() {
        _isPaused = false;
        _overlayPath = null;
      });
    }
  }

  Future<void> _saveToGallery() async {
    if (_videoFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No video to save")),
        );
      }
      return;
    }

    try {
      final file = File(_videoFile!.path);
      if (!await file.exists()) {
        throw Exception("Video file not found");
      }

      print("Attempting to save video from: ${_videoFile!.path}");

      try {
        bool hasPermission = await Gal.hasAccess();
        if (!hasPermission) {
          hasPermission = await Gal.requestAccess();
        }

        if (hasPermission) {
          await Gal.putVideo(_videoFile!.path);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Video saved to gallery successfully!"),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      } catch (galError) {
        print("Gal save failed: $galError");
      }

      print("Gallery save failed, attempting to save to Movies folder...");

      try {
        const String moviesPath = '/storage/emulated/0/Movies';
        final Directory moviesDir = Directory(moviesPath);

        if (!await moviesDir.exists()) {
          await moviesDir.create(recursive: true);
        }

        final String fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final String destinationPath = '$moviesPath/$fileName';

        await file.copy(destinationPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Gallery unavailable. Video saved to Movies folder: $fileName"),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        print("Video saved to Movies folder: $destinationPath");
      } catch (moviesError) {
        print("Movies folder save failed: $moviesError");

        try {
          const String downloadsPath = '/storage/emulated/0/Download';
          final Directory downloadsDir = Directory(downloadsPath);

          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }

          final String fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
          final String destinationPath = '$downloadsPath/$fileName';

          await file.copy(destinationPath);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Video saved to Downloads folder: $fileName"),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 4),
              ),
            );
          }

          print("Video saved to Downloads folder: $destinationPath");
        } catch (downloadsError) {
          throw Exception("Failed to save video anywhere: Gallery failed, Movies folder failed, Downloads failed");
        }
      }
    } catch (e) {
      print("Complete save failure: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save video: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        if (_isPaused && _overlayPath != null)
                          Opacity(
                            opacity: 0.3,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                Colors.white.withOpacity(0.7),
                                BlendMode.modulate,
                              ),
                              child: Image.file(
                                File(_overlayPath!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FloatingActionButton(
                          heroTag: "switch",
                          onPressed: _isRecording ? null : _switchCamera,
                          child: const Icon(Icons.switch_camera),
                        ),
                        FloatingActionButton(
                          heroTag: "record",
                          backgroundColor: _isRecording ? Colors.red : Colors.green,
                          onPressed: _toggleRecording,
                          child: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                        ),
                        if (_isRecording)
                          FloatingActionButton(
                            heroTag: "pause",
                            onPressed: _togglePause,
                            child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                          ),
                        if (!_isRecording && _videoFile != null)
                          FloatingActionButton(
                            heroTag: "save",
                            backgroundColor: Colors.blue,
                            onPressed: _saveToGallery,
                            child: const Icon(Icons.save),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_videoFile != null && !_isRecording)
                  Positioned(
                    top: 50,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Video ready - tap save button",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
