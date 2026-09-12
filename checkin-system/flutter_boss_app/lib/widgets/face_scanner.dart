import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/face_service.dart';

/// กล้องหน้า + ตรวจ liveness + ปุ่มยืนยัน
///
/// ใช้ร่วมกันทั้งตอนลงเวลา (CheckInScreen) และตอนบันทึกใบหน้าอ้างอิง
/// (FaceEnrollScreen) — สองหน้านั้นต่างกันแค่ "ทำอะไรกับรูปที่ถ่ายได้"
/// จึงยกเรื่องกล้องทั้งหมดมาไว้ที่นี่ที่เดียว
///
/// [onCapture] คืน null = สำเร็จ (ผู้เรียกพาออกจากหน้าเอง)
/// คืนข้อความ = ไม่สำเร็จ เอาไปขึ้นเป็นคำแนะนำแล้วเปิดกล้องต่อให้ลองใหม่
class FaceScanner extends StatefulWidget {
  final String confirmLabel;
  final Future<String?> Function(File photo) onCapture;

  /// ข้อความอธิบายเพิ่มใต้ปุ่ม (เช่น เงื่อนไขของการลงเวลา)
  final String? footnote;

  const FaceScanner({
    super.key,
    required this.confirmLabel,
    required this.onCapture,
    this.footnote,
  });

  @override
  State<FaceScanner> createState() => _FaceScannerState();
}

class _FaceScannerState extends State<FaceScanner> {
  CameraController? _controller;
  final FaceService _face = FaceService();

  bool _processing = false;
  bool _submitting = false;
  bool _faceOk = false;
  String _hint = 'จัดใบหน้าให้อยู่ในกรอบ';
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _fatalError = 'ไม่พบกล้องบนเครื่องนี้');
        return;
      }
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.startImageStream(_onImage);
    } catch (err, st) {
      debugPrint('Camera init failed: $err\n$st');
      if (!mounted) return;
      setState(
        () => _fatalError = 'เปิดกล้องไม่ได้ กรุณาอนุญาตสิทธิ์กล้องแล้วลองใหม่',
      );
    }
  }

  Future<void> _onImage(CameraImage image) async {
    if (_processing || _submitting) return;
    _processing = true;
    try {
      final controller = _controller;
      if (controller == null) return;
      final (found, live) = await _face.analyze(
        image,
        controller.description,
        controller.value.deviceOrientation,
      );
      if (!mounted) return;
      setState(() {
        _faceOk = found && live;
        _hint = !found
            ? 'ไม่พบใบหน้า'
            : (!live ? 'กรุณากะพริบตา/มองกล้อง' : 'พร้อมแล้ว ✓');
      });
    } catch (err, st) {
      debugPrint('Face detection error: $err\n$st');
      if (!mounted) return;
      setState(() {
        _faceOk = false;
        _hint = 'ตรวจจับใบหน้าไม่ได้ ลองขยับหน้า/เพิ่มแสง';
      });
    } finally {
      _processing = false;
    }
  }

  Future<void> _restartImageStream() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_onImage);
    } catch (err, st) {
      debugPrint('Restart camera stream failed: $err\n$st');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (!_faceOk || controller == null || _submitting) return;
    setState(() => _submitting = true);

    try {
      // หยุดสตรีมก่อนถ่าย ไม่งั้นกล้องบางรุ่นจะค้างเพราะแย่งบัฟเฟอร์กัน
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final shot =
          await controller.takePicture().timeout(const Duration(seconds: 15));

      final failure = await widget.onCapture(File(shot.path));
      if (!mounted) return;
      if (failure == null) {
        // สำเร็จ — ผู้เรียกกำลังพาออกจากหน้านี้ ปล่อยปุ่มค้างไว้กันกดซ้ำ
        return;
      }
      setState(() {
        _submitting = false;
        _hint = failure;
      });
      await _restartImageStream();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _hint = 'ถ่ายรูปนานเกินไป กรุณาลองใหม่';
      });
      await _restartImageStream();
    } catch (err, st) {
      debugPrint('Capture failed: $err\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _hint = 'ถ่ายรูปไม่สำเร็จ กรุณาลองใหม่';
      });
      await _restartImageStream();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _face.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fatal = _fatalError;
    if (fatal != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 56, color: Colors.orange),
              const SizedBox(height: 12),
              Text(fatal, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(child: CameraPreview(controller)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                _hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _faceOk ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_faceOk && !_submitting) ? _capture : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.confirmLabel),
                ),
              ),
              if (widget.footnote != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.footnote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
