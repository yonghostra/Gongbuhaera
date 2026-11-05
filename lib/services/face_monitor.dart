import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'attention_engine.dart';

/// 전면 카메라로 아이 얼굴을 보고 [FaceSample] 을 흘려보낸다.
///
/// 개인정보: 카메라 영상은 폰 안의 ML Kit 로만 분석하고
/// 저장하거나 서버로 보내지 않는다.
class FaceMonitor {
  CameraController? _controller;
  CameraDescription? _camera;
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // 눈 뜸 확률
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  final _samples = StreamController<FaceSample>.broadcast();
  Stream<FaceSample> get samples => _samples.stream;

  CameraController? get controller => _controller;

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// 분석 간격. 배터리·발열을 줄이려고 초당 3회 정도만 본다.
  static const _interval = Duration(milliseconds: 330);

  Future<void> start() async {
    if (_controller != null) return;
    final cams = await availableCameras();
    if (cams.isEmpty) throw StateError('카메라를 찾을 수 없어요.');
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    final c = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await c.initialize();
    _controller = c;
    await c.startImageStream(_onFrame);
  }

  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> dispose() async {
    await stop();
    await _detector.close();
    await _samples.close();
  }

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRun) < _interval) return;
    _busy = true;
    _lastRun = now;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      if (_samples.isClosed) return;
      _samples.add(_toSample(faces));
    } catch (_) {
      // 프레임 하나 실패는 무시
    } finally {
      _busy = false;
    }
  }

  FaceSample _toSample(List<Face> faces) {
    if (faces.isEmpty) return FaceSample.none;
    // 화면에서 가장 큰 얼굴 = 책상 앞의 아이
    final face = faces.reduce((a, b) =>
        a.boundingBox.width * a.boundingBox.height >=
                b.boundingBox.width * b.boundingBox.height
            ? a
            : b);
    return FaceSample(
      facePresent: true,
      leftEyeOpen: face.leftEyeOpenProbability,
      rightEyeOpen: face.rightEyeOpenProbability,
      headYaw: face.headEulerAngleY,
    );
  }

  /// CameraImage → ML Kit 입력. 앱은 세로 고정이라 기기 회전은 0으로 본다.
  InputImage? _toInputImage(CameraImage image) {
    final cam = _camera;
    if (cam == null) return null;
    final rotation =
        InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    if (rotation == null) return null;

    if (Platform.isIOS) {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format != InputImageFormat.bgra8888 || image.planes.length != 1) {
        return null;
      }
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android: 보통 nv21 한 덩어리로 오지만, 일부 기기는 YUV 3평면으로 준다.
    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else if (image.planes.length == 3) {
      bytes = _yuv420ToNv21(image);
    } else {
      return null;
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  static Uint8List _yuv420ToNv21(CameraImage img) {
    final w = img.width, h = img.height;
    final yP = img.planes[0], uP = img.planes[1], vP = img.planes[2];
    final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));
    var o = 0;
    for (var row = 0; row < h; row++) {
      out.setRange(o, o + w, yP.bytes, row * yP.bytesPerRow);
      o += w;
    }
    final px = uP.bytesPerPixel ?? 1;
    for (var row = 0; row < h ~/ 2; row++) {
      for (var col = 0; col < w ~/ 2; col++) {
        out[o++] = vP.bytes[row * vP.bytesPerRow + col * px];
        out[o++] = uP.bytes[row * uP.bytesPerRow + col * px];
      }
    }
    return out;
  }
}
