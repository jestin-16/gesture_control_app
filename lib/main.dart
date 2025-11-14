import 'dart:async';
import 'dart:typed_data';           // Needed for Uint8List
import 'package:flutter/foundation.dart'; // Needed for WriteBuffer
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

List<CameraDescription>? cameras;

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
      theme: ThemeData.dark(),
      home: const PoseScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PoseScreen extends StatefulWidget {
  const PoseScreen({super.key});

  @override
  _PoseScreenState createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  // === DAY 2 Step 1: Wrist tracking variables ===
  Offset? previousRightWrist;
  Offset? previousLeftWrist;
  DateTime? lastGestureTime;

  late CameraController cameraController;
  bool isBusy = false;
  late PoseDetector poseDetector;

  @override
  void initState() {
    super.initState();

    cameraController = CameraController(
      cameras![0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
      ),
    );

    cameraController.initialize().then((_) {
      if (!mounted) return;

      cameraController.startImageStream((image) {
        if (!isBusy) {
          isBusy = true;
          _processImage(image);
        }
      });

      setState(() {});
    });
  }

  @override
  void dispose() {
    cameraController.dispose();
    poseDetector.close();
    super.dispose();
  }

  // ======================================================
  // DAY 2 — STEP 2: PROCESS IMAGE + DETECT POSES
  // ======================================================
  Future<void> _processImage(CameraImage image) async {
    try {
      final bytes = _concatenatePlanes(image.planes);
      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final poses = await poseDetector.processImage(inputImage);

      for (Pose pose in poses) {
        final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
        final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

        if (rightWrist != null) {
          _detectHandGesture(
            Offset(rightWrist.x, rightWrist.y),
            isRightHand: true,
          );
        }

        if (leftWrist != null) {
          _detectHandGesture(
            Offset(leftWrist.x, leftWrist.y),
            isRightHand: false,
          );
        }
      }
    } catch (e) {
      debugPrint("ERROR: $e");
    } finally {
      isBusy = false;
    }
  }

  // ======================================================
  // DAY 2 — STEP 3: GESTURE DETECTION (SWIPES + LIKE)
  // ======================================================
  void _detectHandGesture(Offset wrist, {required bool isRightHand}) {
    final now = DateTime.now();

    // Limit gesture spam
    if (lastGestureTime != null &&
        now.difference(lastGestureTime!).inMilliseconds < 400) {
      return;
    }

    Offset? previous =
        isRightHand ? previousRightWrist : previousLeftWrist;

    if (previous != null) {
      double dx = wrist.dx - previous.dx; // horizontal movement
      double dy = wrist.dy - previous.dy; // vertical movement

      // 👉 SWIPE RIGHT
      if (dx > 35 && dx.abs() > dy.abs()) {
        print("🔥 GESTURE: SWIPE RIGHT → NEXT");
        lastGestureTime = now;
      }

      // 👈 SWIPE LEFT
      else if (dx < -35 && dx.abs() > dy.abs()) {
        print("🔥 GESTURE: SWIPE LEFT → PREVIOUS");
        lastGestureTime = now;
      }

      // 👆 HAND UP = LIKE
      else if (dy < -40) {
        print("❤️ GESTURE: HAND UP → LIKE");
        lastGestureTime = now;
      }

      // 👇 HAND DOWN = SCROLL DOWN
      else if (dy > 40) {
        print("📜 GESTURE: HAND DOWN → SCROLL DOWN");
        lastGestureTime = now;
      }
    }

    // Save current wrist position
    if (isRightHand) {
      previousRightWrist = wrist;
    } else {
      previousLeftWrist = wrist;
    }
  }

  // ======================================================
  // COMBINE CAMERA IMAGE PLANES
  // ======================================================
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: CameraPreview(cameraController),
    );
  }
}
