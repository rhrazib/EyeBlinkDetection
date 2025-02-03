import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

class EyeBlinkDetectionScreen extends StatefulWidget {
  @override
  _EyeBlinkDetectionScreenState createState() => _EyeBlinkDetectionScreenState();
}

class _EyeBlinkDetectionScreenState extends State<EyeBlinkDetectionScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? cameras;
  int _selectedCameraIndex = 1;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,         // Enables detection of facial landmarks
      enableClassification: true,    // Enables classification (e.g., smiling probability)
      enableTracking: true,
    ),
  );
  bool _isBlinking = false;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  void _requestPermissions() async {


    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      var result = await Permission.camera.request();
      if (result.isDenied) {
        return;
      }
    }

    var photoStatus = await Permission.photos.status;
    if (!photoStatus.isGranted) {
      var result = await Permission.photos.request();
      if (result.isDenied) {
        return;
      }
    }

    if (await Permission.camera.isGranted && await Permission.photos.isGranted) {
      _initializeCamera();
    }
    if (await Permission.contacts.request().isGranted) {
      // Either the permission was already granted before or the user just granted it.
    }

  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    _cameraController = CameraController(
      cameras![_selectedCameraIndex],
      ResolutionPreset.high,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
    });

    _cameraController!.startImageStream((CameraImage image) async {
      if (!_isCameraInitialized || _isProcessing) return;

      _isProcessing = true;

      final inputImage = _convertCameraImage(image);

      final List<Face> faces = await _faceDetector.processImage(inputImage);
      print('Detected faces: ${faces.length}');

      for (final face in faces) {
        if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
          print('Left eye probability: ${face.leftEyeOpenProbability}');
          print('Right eye probability: ${face.rightEyeOpenProbability}');

          if (face.leftEyeOpenProbability! < 0.3 && face.rightEyeOpenProbability! < 0.3) {
            setState(() {
              _isBlinking = true;
            });
            _capturePhoto();
          } else {
            setState(() {
              _isBlinking = false;
            });
          }
        }
      }

      _isProcessing = false;
    });
  }

  InputImage _convertCameraImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final InputImageRotation rotation = _getInputImageRotation();
    final InputImageFormat format = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  InputImageRotation _getInputImageRotation() {
    final cameraSensorOrientation = cameras![0].sensorOrientation;
    switch (cameraSensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }
  void _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isProcessing) {
      return; // Avoid capturing photo while processing
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _cameraController!.takePicture();
      print('Photo captured: ${image.path}');
    } catch (e) {
      print('Error capturing photo: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _swapCamera() async {
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras!.length;
    await _cameraController!.dispose();
    _cameraController = CameraController(
      cameras![_selectedCameraIndex],
      ResolutionPreset.high,
    );
    await _cameraController!.initialize();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Blink Detection'),
        actions: [
          IconButton(
            icon: Icon(Icons.camera_front),
            onPressed: _swapCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(_cameraController!),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _isBlinking ? 'Blinking detected!' : 'No blink detected',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}