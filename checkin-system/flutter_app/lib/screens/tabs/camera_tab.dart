import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/camera.dart';
import '../../services/api_service.dart';

/// ดึงภาพนิ่งถี่แค่ไหน — ถี่กว่านี้เปลืองเน็ตมือถือโดยไม่ได้ภาพลื่นขึ้นจริง
/// (ภาพละ ~35KB ทุก 1 วินาที = ~2MB ต่อนาที)
const Duration _snapshotInterval = Duration(seconds: 1);

/// แตะปุ่มทิศทาง 1 ครั้ง = หมุนสั้นๆ, กดค้าง = หมุนไกลขึ้น
/// เพดานจริงถูกจำกัดอีกชั้นที่เซิร์ฟเวอร์ด้วย CAMERA_PTZ_MAX_DURATION_MS
const int _tapDurationMs = 500;
const int _longPressDurationMs = 1500;

/// ลากนิ้วบนภาพต้องเกินระยะนี้ถึงนับเป็นการสั่งหมุน — กันสั่งพลาดตอนแตะเฉยๆ
const double _dragThreshold = 24;

/// สีพื้นของโซนดูภาพ — จอกล้องควรมืดเพื่อให้เห็นรายละเอียดในภาพชัด
const Color _consoleBg = Color(0xFF10131A);
const Color _consolePanel = Color(0xFF1A1F2B);

/// แท็บ "กล้องวงจรปิด" (หัวหน้าเท่านั้น)
///
/// ภาพเป็นภาพนิ่งที่รีเฟรชเองเรื่อยๆ ไม่ใช่วิดีโอ RTSP — แลกความลื่นกับการ
/// ไม่ต้องพึ่ง plugin วิดีโอ และไม่ต้องเปิดพอร์ตกล้องออกอินเทอร์เน็ต
/// ส่วนเสียงเป็นสตรีมจริงจากไมค์กล้อง ผ่าน ffmpeg ที่เซิร์ฟเวอร์
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> with WidgetsBindingObserver {
  CameraStatus? _status;
  Uint8List? _frame;
  DateTime? _frameAt;

  String? _statusError;
  String? _frameError;
  String? _commandError;

  bool _loadingStatus = true;
  bool _paused = false;

  /// กันไม่ให้รอบถัดไปยิงซ้อนรอบที่ยังไม่จบ (เน็ตช้า/กล้องตอบช้า)
  bool _fetchingFrame = false;

  /// กำลังรอกล้องหมุนอยู่ — ปิดปุ่มไว้ก่อน กันกดรัวจนคำสั่งกองกัน
  bool _moving = false;

  /// ทิศที่เพิ่งสั่งไป ใช้โชว์ลูกศรทับบนภาพให้รู้ว่าคำสั่งไปแล้ว
  String? _lastDirection;

  Timer? _timer;

  // ---- เสียง ----
  AudioPlayer? _player;
  bool _listening = false;
  bool _audioConnecting = false;
  String? _audioError;

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
    _player?.dispose();
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
      // เสียงปล่อยให้เล่นต่อได้ตอนย่อแอป — หัวหน้าอาจอยากฟังเสียงไปทำอย่างอื่นไป
    }
  }

  // -------------------------------------------------------------------
  // ข้อมูล
  // -------------------------------------------------------------------

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
        _frameAt = DateTime.now();
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
      if (action != CameraAction.home) _lastDirection = action;
    });

    try {
      await ApiService.moveCamera(action, durationMs: durationMs);
      // กล้องเพิ่งขยับ — ดึงภาพใหม่ทันทีจะได้เห็นผลโดยไม่ต้องรอรอบถัดไป
      await _fetchFrame();
    } on ApiException catch (err) {
      if (mounted) setState(() => _commandError = err.message);
    } finally {
      if (mounted) setState(() => _moving = false);
      // ลูกศรบนภาพค้างไว้แป๊บนึงแล้วค่อยจาง
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _lastDirection = null);
      });
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

  // -------------------------------------------------------------------
  // เสียงจากไมค์กล้อง
  // -------------------------------------------------------------------

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stopListening();
      return;
    }

    setState(() {
      _audioConnecting = true;
      _audioError = null;
    });

    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioSource(
        AudioSource.uri(
          Uri.parse(ApiService.cameraAudioUrl),
          headers: ApiService.cameraAudioHeaders,
        ),
      );
      unawaited(player.play());
      if (!mounted) return;
      setState(() {
        _listening = true;
        _audioConnecting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _audioConnecting = false;
        _listening = false;
        _audioError = 'ต่อเสียงไม่ได้: $err';
      });
    }
  }

  Future<void> _stopListening() async {
    try {
      await _player?.stop();
    } catch (_) {
      // ปิดเสียงไม่สำเร็จไม่ใช่เรื่องคอขาดบาดตาย
    }
    if (mounted) setState(() => _listening = false);
  }

  // -------------------------------------------------------------------
  // ลากนิ้วบนภาพเพื่อเลื่อนกล้อง
  // -------------------------------------------------------------------

  void _onDragEnd(DragEndDetails details, Offset total) {
    if (_moving) return;

    final dx = total.dx;
    final dy = total.dy;
    if (dx.abs() < _dragThreshold && dy.abs() < _dragThreshold) return;

    // ลากแนวไหนมากกว่าก็เอาแนวนั้น — กันสั่งทแยงแล้วกล้องขยับมั่ว
    final horizontal = dx.abs() >= dy.abs();
    final distance = horizontal ? dx.abs() : dy.abs();

    // ลากไกล = หมุนนาน แต่ไม่เกินเพดานที่เซิร์ฟเวอร์ยอมรับ
    final durationMs = (distance * 4).clamp(300, 2500).toInt();

    // ลากนิ้วไปทางซ้าย = อยากเห็นสิ่งที่อยู่ทางซ้าย = หมุนกล้องไปทางซ้าย
    final String action;
    if (horizontal) {
      action = dx < 0 ? CameraAction.left : CameraAction.right;
    } else {
      action = dy < 0 ? CameraAction.up : CameraAction.down;
    }
    _send(action, durationMs: durationMs);
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _consoleBg,
      child: RefreshIndicator(
        onRefresh: _loadStatus,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildViewport(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildConsole(),
            ),
          ],
        ),
      ),
    );
  }

  /// โซนดูภาพ — ภาพเต็มความกว้าง มีแถบสถานะทับด้านบน/ล่างแบบจอ CCTV
  Widget _buildViewport() {
    final status = _status;
    final live = status?.canControl == true && !_paused && _frame != null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFrameLayer(),
            if (_lastDirection != null) _buildDirectionOverlay(),
            _buildTopBar(live),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameLayer() {
    if (_loadingStatus) {
      return const Center(
        child: Text('กำลังเช็คสถานะกล้อง...',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final status = _status;
    if (_statusError != null || (status != null && !status.canControl)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white38, size: 40),
              const SizedBox(height: 10),
              Text(
                _statusError ?? status!.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadStatus,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('ลองใหม่'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final frame = _frame;
    if (frame == null) {
      return const Center(
        child: Text('กำลังรอภาพจากกล้อง...',
            style: TextStyle(color: Colors.white54)),
      );
    }

    // ลากนิ้วบนภาพ = สั่งกล้องหมุน (เก็บระยะรวมเองเพราะ DragEndDetails
    // ให้มาแต่ความเร็ว ไม่ได้บอกว่าลากไปไกลแค่ไหน)
    Offset total = Offset.zero;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => total = Offset.zero,
      onPanUpdate: (d) => total += d.delta,
      onPanEnd: (d) => _onDragEnd(d, total),
      child: Image.memory(
        frame,
        fit: BoxFit.contain,
        // ไม่ใส่ gaplessPlayback ภาพจะกะพริบขาวทุกรอบที่เปลี่ยนเฟรม
        gaplessPlayback: true,
      ),
    );
  }

  /// ลูกศรจางๆ ทับบนภาพ บอกว่าคำสั่งทิศไหนเพิ่งถูกส่งไป
  Widget _buildDirectionOverlay() {
    const icons = {
      CameraAction.up: Icons.arrow_upward,
      CameraAction.down: Icons.arrow_downward,
      CameraAction.left: Icons.arrow_back,
      CameraAction.right: Icons.arrow_forward,
      CameraAction.zoomIn: Icons.zoom_in,
      CameraAction.zoomOut: Icons.zoom_out,
    };
    final icon = icons[_lastDirection];
    if (icon == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool live) {
    final status = _status;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: live ? Colors.redAccent : Colors.white38,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              live ? 'LIVE' : (_paused ? 'หยุดภาพ' : 'ออฟไลน์'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (_listening) ...[
              const Icon(Icons.volume_up, color: Colors.lightBlueAccent, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              status?.deviceLabel ?? status?.host ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final at = _frameAt;
    final stamp = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}:'
            '${at.second.toString().padLeft(2, '0')}';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _frameError != null
                    ? 'ภาพสะดุด — ยังโชว์ภาพล่าสุด'
                    : 'ลากนิ้วบนภาพเพื่อเลื่อนกล้อง',
                style: TextStyle(
                  color: _frameError != null ? Colors.orangeAccent : Colors.white60,
                  fontSize: 11,
                ),
              ),
            ),
            Text(stamp,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 8),
            InkWell(
              onTap: _status?.canControl == true ? _togglePause : _loadStatus,
              child: Icon(
                _status?.canControl != true
                    ? Icons.refresh
                    : (_paused ? Icons.play_arrow : Icons.pause),
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// แผงควบคุมใต้จอ
  Widget _buildConsole() {
    final status = _status;
    final canControl = status?.canControl ?? false;

    if (!canControl) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _consolePanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDirectionPad(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _consoleButton(
                  label: 'ซูมเข้า',
                  icon: Icons.zoom_in,
                  onTap: () => _send(CameraAction.zoomIn,
                      durationMs: _tapDurationMs),
                  onLongPress: () => _send(CameraAction.zoomIn,
                      durationMs: _longPressDurationMs),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _consoleButton(
                  label: 'ซูมออก',
                  icon: Icons.zoom_out,
                  onTap: () => _send(CameraAction.zoomOut,
                      durationMs: _tapDurationMs),
                  onLongPress: () => _send(CameraAction.zoomOut,
                      durationMs: _longPressDurationMs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAudioRow(),
          const SizedBox(height: 8),
          _consoleButton(
            label: 'สั่งหยุดทันที',
            icon: Icons.pan_tool,
            onTap: _moving ? null : _stop,
            danger: true,
          ),
          const SizedBox(height: 12),
          const Text(
            'แตะ = ขยับนิดเดียว · กดค้าง = ขยับไกลขึ้น · ลากบนภาพ = เลื่อนตามระยะลาก',
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.5),
          ),
          if (_commandError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _commandError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioRow() {
    final status = _status;
    if (status == null || !status.audioSupported) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'เซิร์ฟเวอร์นี้ยังส่งเสียงจากกล้องไม่ได้',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _consoleButton(
          label: _audioConnecting
              ? 'กำลังต่อเสียง...'
              : (_listening ? 'หยุดฟังเสียง' : 'ฟังเสียงจากกล้อง'),
          icon: _listening ? Icons.volume_up : Icons.mic,
          onTap: _audioConnecting ? null : _toggleListen,
          highlight: _listening,
        ),
        if (_audioConnecting)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'กล้องใช้เวลาเริ่มส่งเสียงราว 6 วินาที',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        if (!status.talkbackSupported)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'กล้องรุ่นนี้ไม่มีลำโพง จึงพูดกลับออกกล้องไม่ได้',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        if (_audioError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _audioError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// แป้นทิศทาง — วางเหมือนบนหน้าจอคอม: บน / ซ้าย-กลาง-ขวา / ล่าง
  Widget _buildDirectionPad() {
    return Column(
      children: [
        _padButton(CameraAction.up, Icons.keyboard_arrow_up, 'ขึ้น'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _padButton(
                    CameraAction.left, Icons.keyboard_arrow_left, 'ซ้าย')),
            const SizedBox(width: 8),
            Expanded(
              child: _consoleButton(
                label: 'ตั้งต้น',
                icon: Icons.center_focus_strong,
                onTap: _moving || !(_status?.homeSupported ?? false)
                    ? null
                    : () => _send(CameraAction.home),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: _padButton(
                    CameraAction.right, Icons.keyboard_arrow_right, 'ขวา')),
          ],
        ),
        const SizedBox(height: 8),
        _padButton(CameraAction.down, Icons.keyboard_arrow_down, 'ลง'),
      ],
    );
  }

  Widget _padButton(String action, IconData icon, String label) {
    return _consoleButton(
      label: label,
      icon: icon,
      onTap: () => _send(action, durationMs: _tapDurationMs),
      onLongPress: () => _send(action, durationMs: _longPressDurationMs),
    );
  }

  /// ปุ่มสไตล์แผงควบคุม — สีเข้มเข้ากับจอกล้อง
  ///
  /// ไม่ได้ทำเป็น "หมุนตราบที่ยังกดค้าง" เหมือนบนคอม เพราะบนมือถือถ้าเน็ต
  /// หลุดตอนปล่อยนิ้ว คำสั่งหยุดจะไม่ถึงกล้อง กล้องจะหมุนค้างไปเรื่อยๆ
  Widget _consoleButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool highlight = false,
    bool danger = false,
  }) {
    final enabled = onTap != null && !_moving;
    final Color fg = !enabled
        ? Colors.white24
        : danger
            ? Colors.redAccent
            : highlight
                ? Colors.lightBlueAccent
                : Colors.white;

    return Material(
      color: highlight ? Colors.lightBlueAccent.withValues(alpha: 0.15) : Colors.white10,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
