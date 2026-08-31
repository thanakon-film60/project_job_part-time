import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/camera.dart';
import '../../services/api_service.dart';
import '../../widgets/app_forms.dart';

/// ดึงภาพนิ่งถี่แค่ไหน — ถี่กว่านี้เปลืองเน็ตมือถือโดยไม่ได้ภาพลื่นขึ้นจริง
/// (กล้องส่งภาพละ ~35KB ทุก 1 วินาที = ~2MB ต่อนาที)
const Duration _snapshotInterval = Duration(seconds: 1);

/// กล้องหมุนนานเท่าไรต่อการกด 1 ครั้ง — ค่าจริงถูกจำกัดเพดานที่เซิร์ฟเวอร์อีกชั้น
const int _stepDurationMs = 500;
const int _longStepDurationMs = 1500;

/// แท็บ "กล้องวงจรปิด" (หัวหน้าเท่านั้น)
///
/// ภาพเป็นภาพนิ่งที่รีเฟรชเองเรื่อยๆ ไม่ใช่วิดีโอ RTSP — แลกความลื่นกับการ
/// ไม่ต้องพึ่ง plugin วิดีโอ และไม่ต้องเปิดพอร์ตกล้องออกอินเทอร์เน็ต
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> with WidgetsBindingObserver {
  CameraStatus? _status;
  Uint8List? _frame;

  String? _statusError;
  String? _frameError;
  String? _commandError;

  bool _loadingStatus = true;
  bool _paused = false;

  /// กันไม่ให้รอบถัดไปยิงซ้อนรอบที่ยังไม่จบ (เน็ตช้า/กล้องตอบช้า)
  bool _fetchingFrame = false;

  /// กำลังรอกล้องหมุนอยู่ — ปิดปุ่มไว้ก่อน กันกดรัวจนคำสั่งกองกัน
  bool _moving = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ย่อแอปไปแล้วยังดึงภาพต่อ = เปลืองเน็ตทิ้งเปล่า เพราะไม่มีใครดู
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    if (_paused || !(_status?.canControl ?? false)) return;
    _fetchFrame();
    _timer = Timer.periodic(_snapshotInterval, (_) => _fetchFrame());
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });

    try {
      final status = await ApiService.fetchCameraStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
      _startPolling();
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _statusError = err.message;
        _loadingStatus = false;
      });
    }
  }

  Future<void> _fetchFrame() async {
    if (_fetchingFrame || !mounted) return;
    _fetchingFrame = true;

    try {
      final bytes = await ApiService.fetchCameraSnapshot();
      if (!mounted) return;
      setState(() {
        _frame = bytes;
        _frameError = null;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      // ภาพหลุดเป็นครั้งคราวถือเป็นเรื่องปกติของกล้อง IP — ไม่ล้างภาพเดิมทิ้ง
      // ยังโชว์เฟรมล่าสุดค้างไว้พร้อมข้อความ ดีกว่าจอดำกะพริบ
      setState(() => _frameError = err.message);
    } finally {
      _fetchingFrame = false;
    }
  }

  Future<void> _send(String action, {int? durationMs}) async {
    if (_moving) return;
    setState(() {
      _moving = true;
      _commandError = null;
    });

    try {
      await ApiService.moveCamera(action, durationMs: durationMs);
      // กล้องเพิ่งขยับ — ดึงภาพใหม่ทันทีจะได้เห็นผลโดยไม่ต้องรอรอบถัดไป
      await _fetchFrame();
    } on ApiException catch (err) {
      if (mounted) setState(() => _commandError = err.message);
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _stop() async {
    try {
      await ApiService.stopCamera();
    } on ApiException catch (err) {
      if (mounted) setState(() => _commandError = err.message);
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      _startPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildVideoCard(),
          _buildControlCard(),
        ],
      ),
    );
  }

  Widget _buildVideoCard() {
    final status = _status;

    return SectionCard(
      title: 'ภาพจากกล้อง',
      icon: Icons.videocam,
      trailing: status?.canControl == true
          ? IconButton(
              tooltip: _paused ? 'เล่นต่อ' : 'หยุดภาพชั่วคราว',
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              onPressed: _togglePause,
            )
          : IconButton(
              tooltip: 'โหลดใหม่',
              icon: const Icon(Icons.refresh),
              onPressed: _loadStatus,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingStatus)
            const NoticeBox.loading(text: 'กำลังเช็คสถานะกล้อง...')
          else if (_statusError != null)
            NoticeBox.error(text: _statusError!, onRetry: _loadStatus)
          else if (status != null && !status.canControl)
            NoticeBox.error(text: status.message, onRetry: _loadStatus)
          else
            _buildFrame(),
          if (status != null && status.canControl) ...[
            const SizedBox(height: 8),
            InfoRow(
              label: 'กล้อง',
              value: status.deviceLabel ?? status.host,
            ),
            if (_paused)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'หยุดภาพไว้ชั่วคราว — กดปุ่มเล่นเพื่อดูต่อ',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              )
            else if (_frameError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'ภาพสะดุด: $_frameError',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFrame() {
    final frame = _frame;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: frame == null
            ? const Center(
                child: Text(
                  'กำลังรอภาพจากกล้อง...',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : Image.memory(
                frame,
                fit: BoxFit.contain,
                // ไม่ใส่ gaplessPlayback ภาพจะกะพริบขาวทุกรอบที่เปลี่ยนเฟรม
                gaplessPlayback: true,
              ),
      ),
    );
  }

  Widget _buildControlCard() {
    final canControl = _status?.canControl ?? false;

    return SectionCard(
      title: 'ควบคุมกล้อง',
      icon: Icons.control_camera,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canControl)
            const NoticeBox.empty(text: 'ต่อกล้องไม่ได้ จึงยังสั่งหมุนไม่ได้')
          else ...[
            _buildDirectionPad(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ptzButton(
                    label: 'ซูมเข้า',
                    icon: Icons.zoom_in,
                    action: CameraAction.zoomIn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ptzButton(
                    label: 'ซูมออก',
                    icon: Icons.zoom_out,
                    action: CameraAction.zoomOut,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _moving ? null : _stop,
              icon: const Icon(Icons.pan_tool, size: 18),
              label: const Text('สั่งหยุดทันที'),
            ),
            const SizedBox(height: 10),
            const Text(
              'กด 1 ครั้ง = หมุนสั้นๆ · กดค้าง = หมุนไกลขึ้น',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_commandError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _commandError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// แป้นทิศทาง — วางเหมือนบนหน้าจอคอม: บน / ซ้าย-กลาง-ขวา / ล่าง
  Widget _buildDirectionPad() {
    return Column(
      children: [
        _ptzButton(
          label: 'ขึ้น',
          icon: Icons.keyboard_arrow_up,
          action: CameraAction.up,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ptzButton(
                label: 'ซ้าย',
                icon: Icons.keyboard_arrow_left,
                action: CameraAction.left,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _moving || !(_status?.homeSupported ?? false)
                    ? null
                    : () => _send(CameraAction.home),
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('ตั้งต้น'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ptzButton(
                label: 'ขวา',
                icon: Icons.keyboard_arrow_right,
                action: CameraAction.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ptzButton(
          label: 'ลง',
          icon: Icons.keyboard_arrow_down,
          action: CameraAction.down,
        ),
      ],
    );
  }

  /// ปุ่มสั่งกล้อง 1 ทิศ — แตะสั้น = ขยับนิดเดียว, กดค้าง = ขยับไกลขึ้น
  ///
  /// ไม่ได้ทำเป็น "หมุนตราบที่ยังกดค้าง" เหมือนบนคอม เพราะบนมือถือถ้าเน็ต
  /// หลุดตอนปล่อยนิ้ว คำสั่งหยุดจะไม่ถึงกล้อง กล้องจะหมุนค้างไปเรื่อยๆ
  Widget _ptzButton({
    required String label,
    required IconData icon,
    required String action,
  }) {
    return FilledButton.tonalIcon(
      onPressed:
          _moving ? null : () => _send(action, durationMs: _stepDurationMs),
      onLongPress:
          _moving ? null : () => _send(action, durationMs: _longStepDurationMs),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}
