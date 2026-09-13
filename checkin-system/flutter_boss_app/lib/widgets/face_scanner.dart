import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/face_framing.dart';
import '../services/face_service.dart';

/// กล้องหน้า + กรอบวงรีบังคับตำแหน่งใบหน้า + ตรวจท่าตามคำสั่ง + ปุ่มยืนยัน
///
/// ใช้ร่วมกัน 3 หน้า: ลงทะเบียนใบหน้า, ลงเวลาเข้า-ออกงาน, ยืนยันว่าอยู่บ้าน
/// สองหน้าแรกไม่มีคำสั่งท่าทาง ([challengeAction] เป็น null) จะได้พฤติกรรมเดิม
/// คือแค่ต้องจัดหน้าให้อยู่ในกรอบแล้วกดปุ่มเอง
///
/// [onCapture] คืน null = สำเร็จ (ผู้เรียกพาออกจากหน้าเอง)
/// คืนข้อความ = ไม่สำเร็จ เอาไปขึ้นเป็นคำแนะนำแล้วเปิดกล้องต่อให้ลองใหม่
class FaceScanner extends StatefulWidget {
  final String confirmLabel;
  final Future<String?> Function(File photo) onCapture;

  /// ข้อความอธิบายเพิ่มใต้ปุ่ม (เช่น เงื่อนไขของการลงเวลา)
  final String? footnote;

  /// คำสั่งท่าทางจาก server เช่น "กะพริบตา 2 ครั้ง" — null = ไม่ต้องทำท่า
  final String? challengeAction;

  /// รหัสท่าจาก server (ถ้ามี) ใช้แทนการเดาจากข้อความไทย
  final String? challengeCode;

  /// ถ่ายเองอัตโนมัติเมื่อจัดกรอบพอดีและทำท่าครบ
  final bool autoCapture;

  const FaceScanner({
    super.key,
    required this.confirmLabel,
    required this.onCapture,
    this.footnote,
    this.challengeAction,
    this.challengeCode,
    this.autoCapture = true,
  });

  @override
  State<FaceScanner> createState() => _FaceScannerState();
}

/// หน่วงก่อนถ่ายอัตโนมัติ — ให้ผู้ใช้เห็นว่า "พร้อมแล้ว" ก่อนชัตเตอร์ลั่น
/// ไม่งั้นจะรู้สึกเหมือนระบบแอบถ่าย
const int _autoCaptureCountdown = 3;

class _FaceScannerState extends State<FaceScanner> {
  CameraController? _controller;
  final FaceService _face = FaceService();
  late FaceChallenge _challenge;

  static const _target = FaceFrameTarget();

  bool _processing = false;
  bool _submitting = false;

  FaceObservation _observation = const FaceObservation.none();
  FaceFraming _framing = FaceFraming.noFace;
  String? _failureHint;
  String? _fatalError;

  Timer? _countdownTimer;
  int _countdown = _autoCaptureCountdown;

  bool get _ready => _framing.isOk && _challenge.isSatisfied;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challengeAction == null
        ? FaceChallenge.none()
        : FaceChallenge.fromAction(
            widget.challengeAction!,
            code: widget.challengeCode,
          );
    _initCamera();
  }

  @override
  void didUpdateWidget(covariant FaceScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // server ออกโจทย์ใหม่ = ต้องเริ่มนับท่าใหม่ทั้งหมด ห้ามใช้ผลของโจทย์เก่า
    if (oldWidget.challengeAction != widget.challengeAction ||
        oldWidget.challengeCode != widget.challengeCode) {
      _challenge = widget.challengeAction == null
          ? FaceChallenge.none()
          : FaceChallenge.fromAction(
              widget.challengeAction!,
              code: widget.challengeCode,
            );
      _cancelCountdown();
    }
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
      final observation = await _face.observe(
        image,
        controller.description,
        controller.value.deviceOrientation,
      );
      if (!mounted) return;

      final framing = evaluateFraming(observation, target: _target);
      // ต้องอยู่ในกรอบก่อนถึงจะเริ่มนับท่า — กันคนโบกหน้าผ่าน ๆ แล้วนับว่าทำท่าแล้ว
      if (framing.isOk) {
        _challenge.update(observation);
      }

      setState(() {
        _observation = observation;
        _framing = framing;
      });
      _syncCountdown();
    } catch (err, st) {
      debugPrint('Face detection error: $err\n$st');
      if (!mounted) return;
      setState(() {
        _observation = const FaceObservation.none();
        _framing = FaceFraming.noFace;
      });
      _cancelCountdown();
    } finally {
      _processing = false;
    }
  }

  /// เริ่ม/หยุดนับถอยหลังตามความพร้อม — หลุดกรอบกลางคันต้องยกเลิก ไม่ใช่ถ่ายต่อ
  void _syncCountdown() {
    if (!widget.autoCapture || _submitting) return;
    if (_ready) {
      if (_countdownTimer != null) return;
      setState(() => _countdown = _autoCaptureCountdown);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (!_ready) {
          _cancelCountdown();
          return;
        }
        setState(() => _countdown--);
        if (_countdown <= 0) {
          _cancelCountdown();
          _capture();
        }
      });
    } else {
      _cancelCountdown();
    }
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted && _countdown != _autoCaptureCountdown) {
      setState(() => _countdown = _autoCaptureCountdown);
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
    if (!_ready || controller == null || _submitting) return;
    setState(() {
      _submitting = true;
      _failureHint = null;
    });
    _cancelCountdown();

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
      // ส่งไม่ผ่าน = ต้องทำท่าใหม่ทั้งหมด ห้ามให้กดซ้ำด้วยผลของท่าเดิม
      _challenge.reset();
      setState(() {
        _submitting = false;
        _failureHint = failure;
      });
      await _restartImageStream();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failureHint = 'ถ่ายรูปนานเกินไป กรุณาลองใหม่';
      });
      await _restartImageStream();
    } catch (err, st) {
      debugPrint('Capture failed: $err\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failureHint = 'ถ่ายรูปไม่สำเร็จ กรุณาลองใหม่';
      });
      await _restartImageStream();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller?.dispose();
    _face.dispose();
    super.dispose();
  }

  /// ข้อความที่ควรแสดงตอนนี้ — เรียงลำดับให้ผู้ใช้แก้ทีละอย่าง
  String get _hint {
    final failure = _failureHint;
    if (failure != null) return failure;
    if (_submitting) return 'กำลังยืนยันตัวตน...';
    if (!_framing.isOk) return _framing.hint;
    if (!_challenge.isSatisfied) return _challenge.hintFor(_observation);
    return widget.autoCapture ? 'พร้อมแล้ว — อย่าขยับ' : 'พร้อมแล้ว ✓';
  }

  Color get _statusColor {
    if (_failureHint != null) return Colors.redAccent;
    if (_ready) return Colors.green;
    if (_framing.isOk) return Colors.orange;
    return Colors.redAccent;
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

    final counting = _countdownTimer != null;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              // หน้ากากทึบเจาะวงรี — บอกด้วยภาพว่าต้องเอาหน้าไปวางตรงไหน
              CustomPaint(
                painter: _OvalMaskPainter(
                  target: _target,
                  color: _statusColor,
                  progress: _framing.isOk
                      ? progressOf(_challenge, _observation)
                      : 0,
                ),
              ),
              if (counting)
                Align(
                  alignment: const Alignment(0, 0.55),
                  child: _CountdownBadge(seconds: _countdown),
                ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Text(
                _hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _statusColor,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_ready && !_submitting) ? _capture : null,
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

/// วาดพื้นทึบแล้วเจาะวงรีตรงกลาง + ขอบบอกสถานะ + ส่วนโค้งบอกความคืบหน้า
class _OvalMaskPainter extends CustomPainter {
  final FaceFrameTarget target;
  final Color color;
  final double progress;

  const _OvalMaskPainter({
    required this.target,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final oval = target.ovalIn(size);

    // เจาะรู: เอาสี่เหลี่ยมเต็มจอ ลบด้วยวงรี แล้วระบายส่วนที่เหลือ
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(oval),
    );
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.9),
    );

    if (progress > 0) {
      canvas.drawArc(
        oval,
        -1.5708, // เริ่มที่ 12 นาฬิกา
        6.2832 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OvalMaskPainter old) =>
      old.color != color || old.progress != progress || old.target != target;
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;

  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.green, width: 3),
      ),
      child: Text(
        '$seconds',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
