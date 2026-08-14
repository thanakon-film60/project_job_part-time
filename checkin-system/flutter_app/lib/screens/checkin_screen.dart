import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/face_service.dart';

/// หน้าจอสแกนใบหน้า: เปิดกล้องหน้า ตรวจ liveness แล้วถ่ายรูปส่งเช็คอิน
class CheckInScreen extends StatefulWidget {
  final String kind; // "in" หรือ "out"
  final double latitude;
  final double longitude;

  const CheckInScreen({
    super.key,
    required this.kind,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  CameraController? _controller;
  final FaceService _face = FaceService();
  bool _processing = false;
  bool _submitting = false;
  bool _faceOk = false;
  String _hint = 'จัดใบหน้าให้อยู่ในกรอบ';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
    _controller!.startImageStream(_onImage);
  }

  Future<void> _onImage(CameraImage image) async {
    if (_processing || _submitting) return;
    _processing = true;
    try {
      final (found, live) =
          await _face.analyze(image, _controller!.description);
      if (mounted) {
        setState(() {
          _faceOk = found && live;
          _hint = !found
              ? 'ไม่พบใบหน้า'
              : (!live ? 'กรุณากะพริบตา/มองกล้อง' : 'พร้อมแล้ว ✓');
        });
      }
    } catch (_) {
    } finally {
      _processing = false;
    }
  }

  Future<void> _capture() async {
    if (!_faceOk || _controller == null) return;
    setState(() => _submitting = true);
    await _controller!.stopImageStream();
    final shot = await _controller!.takePicture();

    final (ok, msg) = await ApiService.checkIn(
      lat: widget.latitude,
      lng: widget.longitude,
      kind: widget.kind,
      faceDetected: true,
      photo: File(shot.path),
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _hint = msg;
      });
      _controller!.startImageStream(_onImage);
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
    final ready = _controller?.value.isInitialized ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == 'in' ? 'สแกนหน้า - เข้างาน' : 'สแกนหน้า - ออกงาน'),
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: CameraPreview(_controller!)),
                Container(
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        _hint,
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
                          onPressed:
                              (_faceOk && !_submitting) ? _capture : null,
                          child: _submitting
                              ? const CircularProgressIndicator()
                              : Text(widget.kind == 'in'
                                  ? 'ยืนยันเข้างาน'
                                  : 'ยืนยันออกงาน'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
