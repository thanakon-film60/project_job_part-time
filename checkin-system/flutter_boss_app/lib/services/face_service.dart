import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// สิ่งที่ ML Kit เห็นในเฟรมหนึ่ง
///
/// แยกออกมาเป็นคลาสเพื่อให้ตรรกะจัดกรอบ/ตรวจท่าทางเขียนเป็นฟังก์ชันบริสุทธิ์
/// และเขียนเทสต์ได้โดยไม่ต้องมีกล้องจริง
class FaceObservation {
  final int faceCount;

  /// กรอบใบหน้า **ในพิกัดของภาพหลังหมุนแล้ว** (ดู [frame])
  final Rect? box;

  /// ขนาดภาพหลังหมุนแล้ว — ใช้แปลง [box] เป็นสัดส่วน 0..1
  final Size? frame;

  final double? leftEyeOpen;
  final double? rightEyeOpen;

  /// หันซ้าย-ขวา (`headEulerAngleY`) หน่วยองศา
  ///
  /// ⚠️ เครื่องหมายบวก/ลบขึ้นกับกล้องหน้า/หลังและการ mirror ของ preview
  /// จึงไม่ควรผูกทิศทางตายตัว — ดู `FaceChallenge` ที่บอกผู้ใช้ว่า "หันอีกทาง"
  /// เมื่อหันผิดข้าง แทนที่จะเงียบแล้วไม่ผ่าน
  final double? yaw;

  /// เอียงหัวซ้าย-ขวา (`headEulerAngleZ`) หน่วยองศา
  final double? roll;

  const FaceObservation({
    required this.faceCount,
    this.box,
    this.frame,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.yaw,
    this.roll,
  });

  const FaceObservation.none() : this(faceCount: 0);

  bool get hasFace => faceCount > 0;
  bool get hasOneFace => faceCount == 1 && box != null && frame != null;

  /// จุดกึ่งกลางใบหน้าเป็นสัดส่วน 0..1 ของภาพ
  Offset? get center {
    final b = box, f = frame;
    if (b == null || f == null || f.width <= 0 || f.height <= 0) return null;
    return Offset(b.center.dx / f.width, b.center.dy / f.height);
  }

  /// ความกว้างใบหน้าเทียบกับความกว้างภาพ (0..1) — ใช้บอกว่าใกล้/ไกลไป
  double? get widthRatio {
    final b = box, f = frame;
    if (b == null || f == null || f.width <= 0) return null;
    return b.width / f.width;
  }

  /// ค่าเฉลี่ยความน่าจะเป็นที่ตาเปิด — null เมื่อ ML Kit อ่านไม่ได้
  double? get eyeOpenness {
    final l = leftEyeOpen, r = rightEyeOpen;
    if (l == null && r == null) return null;
    if (l == null) return r;
    if (r == null) return l;
    return (l + r) / 2;
  }
}

/// ตรวจจับใบหน้าด้วย Google ML Kit
///
/// **ไม่ได้ตัดสินว่าเป็นคนจริงหรือเป็นเจ้าของบัญชี** — หน้าที่ของคลาสนี้คือ
/// รายงานสิ่งที่เห็นเท่านั้น การตัดสินอยู่ที่ `FaceFraming` และ `FaceChallenge`
class FaceService {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      // ต้องเปิดถึงจะได้ leftEyeOpenProbability / rightEyeOpenProbability
      // ซึ่งเป็นหัวใจของการตรวจกะพริบตา
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  /// อ่านเฟรมหนึ่งแล้วคืนสิ่งที่เห็น
  Future<FaceObservation> observe(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    final rotation = _rotationOf(camera, deviceOrientation);
    if (rotation == null) return const FaceObservation.none();

    final input = _toInputImage(image, rotation);
    if (input == null) return const FaceObservation.none();

    final faces = await _detector.processImage(input);
    if (faces.isEmpty) return const FaceObservation.none();
    if (faces.length > 1) return FaceObservation(faceCount: faces.length);

    // ML Kit คืนกรอบในพิกัดของภาพ "หลังหมุน" แล้ว ถ้าหมุน 90/270 องศา
    // ด้านกว้าง-สูงจะสลับกัน ต้องสลับตามไม่งั้นสัดส่วนที่คำนวณจะผิดแกน
    final swapped = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final frame = swapped
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());

    final f = faces.first;
    return FaceObservation(
      faceCount: 1,
      box: f.boundingBox,
      frame: frame,
      leftEyeOpen: f.leftEyeOpenProbability,
      rightEyeOpen: f.rightEyeOpenProbability,
      yaw: f.headEulerAngleY,
      roll: f.headEulerAngleZ,
    );
  }

  InputImageRotation? _rotationOf(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (!Platform.isAndroid) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    final compensation = _orientations[deviceOrientation];
    if (compensation == null) return null;
    final raw = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + compensation) % 360
        : (camera.sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(raw);
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void dispose() => _detector.close();
}
