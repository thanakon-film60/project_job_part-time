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
  CheckInResult? _savedResult;
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
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
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
      final (found, live) = await _face.analyze(
        image,
        _controller!.description,
        _controller!.value.deviceOrientation,
      );
      if (mounted) {
        setState(() {
          _faceOk = found && live;
          _hint = !found
              ? 'ไม่พบใบหน้า'
              : (!live ? 'กรุณากะพริบตา/มองกล้อง' : 'พร้อมแล้ว ✓');
        });
      }
    } catch (e, st) {
      debugPrint('Face detection error: $e\n$st');
      if (mounted) {
        setState(() {
          _faceOk = false;
          _hint = 'ตรวจจับใบหน้าไม่ได้ ลองขยับหน้า/เพิ่มแสง';
        });
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _capture() async {
    if (!_faceOk || _controller == null) return;
    setState(() => _submitting = true);
    await _controller!.stopImageStream();
    final shot = await _controller!.takePicture();

    final result = await ApiService.checkIn(
      lat: widget.latitude,
      lng: widget.longitude,
      kind: widget.kind,
      faceDetected: true,
      photo: File(shot.path),
    );

    if (!mounted) return;
    if (result.success) {
      await _controller?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _submitting = false;
        _savedResult = result;
      });
    } else {
      setState(() {
        _submitting = false;
        _hint = result.message;
      });
      _controller!.startImageStream(_onImage);
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(local.hour)}:${pad(local.minute)} น. '
        '${pad(local.day)}/${pad(local.month)}/${local.year + 543}';
  }

  String _formatDistance(double? distanceKm) {
    if (distanceKm == null) return '-';
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} เมตร';
    }
    return '${distanceKm.toStringAsFixed(2)} กม.';
  }

  Widget _buildSuccess(CheckInResult result) {
    final action = result.kind == 'out' ? 'ออกงาน' : 'เข้างาน';
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกเสร็จแล้ว')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 84, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'บันทึกเสร็จแล้ว',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('ระบบบันทึกการ$actionของคุณแล้ว'),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('ช่วงเวลา'),
                        subtitle: Text(_formatTime(result.timestamp)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.place),
                        title: const Text('จุดทำงาน'),
                        subtitle: Text(result.officeName ?? '-'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.social_distance),
                        title: const Text('ระยะทาง'),
                        subtitle: Text(_formatDistance(result.distanceKm)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('กลับหน้าแรก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _face.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedResult = _savedResult;
    if (savedResult != null) return _buildSuccess(savedResult);

    final ready = _controller?.value.isInitialized ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.kind == 'in' ? 'สแกนหน้า - เข้างาน' : 'สแกนหน้า - ออกงาน'),
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
