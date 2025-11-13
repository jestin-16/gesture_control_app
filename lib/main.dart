import 'dart:typed_data';
import 'dart:ui';
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
      debugShowCheckedModeBanner: false,
      home: const PoseScreen(),
    );
  }
}

class PoseScreen extends StatefulWidget {
  const PoseScreen({super.key});
  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  CameraController? _cameraController;

  final options = PoseDetectorOptions(
    mode: PoseDetectionMode.stream,
  );

  late PoseDetector _poseDetector;

  bool isBusy = false;
  List<PoseLandmark>? handPoints;

  @override
  void initState() {
    super.initState();
    _poseDetector = PoseDetector(options: options);
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameraController = CameraController(
      cameras![1],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    _cameraController!.startImageStream((CameraImage image) {
      _processImage(image);
    });

    setState(() {});
  }

  Future<void> _processImage(CameraImage image) async {
    if (isBusy) return;
    isBusy = true;

    final bytes = _concatenatePlanes(image.planes);

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      inputImageData: _buildMetaData(image),
    );

    final poses = await _poseDetector.processImage(inputImage);

    if (poses.isNotEmpty) {
      final pose = poses.first;

      // extract important hand landmarks
      handPoints = [
        pose.landmarks[PoseLandmarkType.leftWrist]!,
        pose.landmarks[PoseLandmarkType.leftThumb]!,
        pose.landmarks[PoseLandmarkType.leftIndex]!,
        pose.landmarks[PoseLandmarkType.leftPinky]!,
      ];
    } else {
      handPoints = null;
    }

    isBusy = false;
    setState(() {});
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer buffer = WriteBuffer();
    for (Plane p in planes) {
      buffer.putUint8List(p.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  InputImageData _buildMetaData(CameraImage image) {
    return InputImageData(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      imageRotation: InputImageRotation.rotation0deg,
      inputImageFormat: InputImageFormat.nv21,
      planeData: image.planes
          .map((plane) => InputImagePlaneMetadata(
                bytesPerRow: plane.bytesPerRow,
                height: plane.height,
                width: plane.width,
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_cameraController!),

          if (handPoints != null)
            CustomPaint(
              painter: HandPainter(
                points: handPoints!,
                previewSize: _cameraController!.value.previewSize!,
              ),
            ),
        ],
      ),
    );
  }
}

class HandPainter extends CustomPainter {
  final List<PoseLandmark> points;
  final Size previewSize;

  HandPainter({required this.points, required this.previewSize});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / previewSize.height;
    final scaleY = size.height / previewSize.width;

    final pointPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 10
      ..style = PaintingStyle.fill;

    for (var p in points) {
      canvas.drawCircle(
        Offset(p.x * scaleX, p.y * scaleY),
        6,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
