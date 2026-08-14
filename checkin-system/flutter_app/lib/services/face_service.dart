import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ตรวจจับใบหน้า + liveness อย่างง่าย ด้วย Google ML Kit
/// (ตรวจว่ามีใบหน้าจริง 1 หน้า และตา/รอยยิ้มขยับ = คนจริง ไม่ใช่รูปถ่าย)
class FaceService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // ได้ค่า eyeOpenProbability / smiling
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  /// คืน (พบใบหน้า 1 หน้า, ผ่าน liveness)
  Future<(bool faceFound, bool livenessOk)> analyze(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final input = _toInputImage(image, camera);
    if (input == null) return (false, false);

    final faces = await _detector.processImage(input);
    if (faces.length != 1) return (faces.isNotEmpty, false);

    final f = faces.first;
    // liveness อย่างง่าย: ตรวจว่าตรวจจับความน่าจะเป็นตาเปิด/ยิ้มได้
    final leftEye = f.leftEyeOpenProbability;
    final rightEye = f.rightEyeOpenProbability;
    final live = leftEye != null &&
        rightEye != null &&
        (leftEye > 0.4 || rightEye > 0.4);
    return (true, live);
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void dispose() => _detector.close();
}
