import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/background_service.dart';
import '../services/location_service.dart';
import '../widgets/today_attendance_card.dart';
import '../widgets/tracking_status_card.dart';
import 'checkin_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ---- ตำแหน่งปัจจุบัน / geofence ----
  Position? _pos;
  double? _distanceKm;
  double? _allowedRadiusKm;
  double? _workDistanceKm;
  String? _nearestOfficeName;
  bool _within = false;
  bool _withinWork = false;
  String _status = 'กำลังหาตำแหน่ง...';
  StreamSubscription<Position>? _positionSub;

  // ---- การติดตามตำแหน่งเบื้องหลัง (ล็อกอิน -> ออกจากระบบ) ----
  LocationAccess _access = LocationAccess.denied;
  bool _trackingRunning = false;
  bool _preparingTracking = false;
  DateTime? _lastPingAt;
  StreamSubscription<TrackingUpdate>? _trackingSub;
  bool _askedBatteryExemption = false;
  bool _permissionDialogOpen = false;

  // ---- การลงเวลาของวันนี้ ----
  DayAttendance? _today;
  bool _loadingToday = false;
  String? _todayError;

  Timer? _sessionTimer;
  Timer? _permissionNagTimer;
  Timer? _attendanceTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armSessionTimer();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _setupTracking(promptIfMissing: true);
    await _loadToday();
    _startPeriodicWork();
  }

  /// ตัวจับเวลาที่ต้องเดินตลอดเวลาที่ยังล็อกอินอยู่
  void _startPeriodicWork() {
    // ทวงสิทธิ์ "อนุญาตตลอดเวลา" ซ้ำเรื่อยๆ จนกว่าจะได้ หรือจนออกจากระบบ
    _permissionNagTimer?.cancel();
    _permissionNagTimer = Timer.periodic(
      Config.locationPermissionNagInterval,
      (_) => _nagForAlwaysPermission(),
    );

    _attendanceTimer?.cancel();
    _attendanceTimer = Timer.periodic(
      Config.attendanceRefreshInterval,
      (_) => _loadToday(),
    );

    // เดินนาฬิกา "รวมเวลาทำงานวันนี้" และความสดของ ping
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(Config.workedClockTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timer ไม่เดินตอนแอปถูกพักไว้ (หรือเครื่องดับไปทั้งคืน)
    // กลับมาเมื่อไหร่จึงต้องเทียบเวลาใหม่ทุกครั้ง
    if (state != AppLifecycleState.resumed) return;
    _armSessionTimer();
    // ผู้ใช้อาจเพิ่งไปกด "อนุญาตตลอดเวลา" ในหน้าตั้งค่ามา
    _setupTracking();
    _loadToday();
  }

  /// ตั้งเวลาเด้งออกจากระบบตอน 4 ทุ่ม (ดู Config.sessionEndHour)
  void _armSessionTimer() {
    _sessionTimer?.cancel();
    final left = ApiService.timeLeftInSession;
    if (left == null || left <= Duration.zero) {
      // หมดเวลาไปแล้ว — เด้งออกในเฟรมถัดไป (ห้ามสั่ง Navigator กลางการ build)
      _sessionTimer = Timer(Duration.zero, _forceLogout);
      return;
    }
    _sessionTimer = Timer(left, _forceLogout);
  }

  Future<void> _forceLogout() async {
    _sessionTimer?.cancel();
    await stopBackgroundService();
    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          notice: Config.sessionExpiredMessage,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    await stopBackgroundService();
    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // -------------------------------------------------------------------
  // การติดตามตำแหน่ง
  //
  // เริ่มตั้งแต่เข้าหน้านี้ (= ล็อกอินสำเร็จ) ไม่ต้องรอเช็คอิน และไม่สนใจว่า
  // อยู่ในเขตหรือไม่ — อยู่บ้านก็ยังถูกติดตามจนกว่าจะออกจากระบบ/ถึง 4 ทุ่ม
  // -------------------------------------------------------------------
  Future<void> _setupTracking({bool promptIfMissing = false}) async {
    if (mounted) setState(() => _preparingTracking = true);
    try {
      await _setupTrackingSteps(promptIfMissing: promptIfMissing);
    } finally {
      if (mounted) setState(() => _preparingTracking = false);
    }
  }

  Future<void> _setupTrackingSteps({required bool promptIfMissing}) async {
    var access = promptIfMissing
        ? await LocationService.requestWhileInUse()
        : await LocationService.check();

    // ได้แค่ "ตอนเปิดแอป" ยังไม่พอ ต้องดัน "ตลอดเวลา" ต่อทุกครั้งที่มีโอกาส
    if (access.canTrack && !access.isAlways) {
      access = await LocationService.requestAlways();
    }
    if (!mounted) return;
    setState(() => _access = access);

    if (!access.canTrack) {
      setState(() => _status = access.message);
      await _stopTracking();
      if (promptIfMissing) await _showPermissionDialog(access);
      return;
    }

    // Android หลายรุ่นฆ่า service เบื้องหลังทิ้งเพราะโหมดประหยัดแบต — ขอยกเว้นครั้งเดียว
    if (promptIfMissing && !_askedBatteryExemption) {
      _askedBatteryExemption = true;
      await LocationService.requestBatteryExemption();
    }

    await _startTracking();
    await _refreshOffices();
    await _watchPositions();

    if (!access.isAlways && promptIfMissing) {
      await _showPermissionDialog(access);
    }
  }

  Future<void> _startTracking() async {
    try {
      final started = await initBackgroundService();
      _trackingSub ??= trackingUpdates().listen((update) {
        if (!mounted) return;
        setState(() {
          _trackingRunning = true;
          if (!update.isError) _lastPingAt = update.sentAt;
        });
      });
      final running = started && await isTrackingRunning();
      final last = await lastTrackingUpdate();
      if (!mounted) return;
      setState(() {
        _trackingRunning = running;
        _lastPingAt = last.sentAt ?? _lastPingAt;
      });
    } catch (err) {
      debugPrint('Background service failed to start: $err');
      if (!mounted) return;
      setState(() => _trackingRunning = false);
    }
  }

  Future<void> _stopTracking() async {
    await stopBackgroundService();
    if (!mounted) return;
    setState(() {
      _trackingRunning = false;
      _lastPingAt = null;
    });
  }

  /// ทวงสิทธิ์ซ้ำระหว่างวัน — หยุดทวงเมื่อได้สิทธิ์แล้วหรือออกจากระบบแล้ว
  Future<void> _nagForAlwaysPermission() async {
    if (!ApiService.isLoggedIn) return;
    final access = await LocationService.check();
    if (!mounted) return;
    setState(() => _access = access);
    if (access.isAlways && _trackingRunning) return;
    await _setupTracking(promptIfMissing: true);
  }

  Future<void> _showPermissionDialog(LocationAccess access) async {
    if (!mounted || _permissionDialogOpen) return;
    _permissionDialogOpen = true;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ต้องอนุญาตตำแหน่งตลอดเวลา'),
        content: Text(
          '${access.message}\n\n'
          'ระบบต้องบันทึกตำแหน่งต่อเนื่องตั้งแต่เข้าสู่ระบบจนกว่าจะออกจากระบบ '
          'ไม่ว่าจะอยู่ที่ทำงานหรืออยู่บ้าน '
          'กรุณาเลือก "อนุญาตตลอดเวลา" ในหน้าตั้งค่าสิทธิ์ตำแหน่ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('later'),
            child: const Text('ไว้ทีหลัง'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              access == LocationAccess.serviceOff ? 'gps' : 'settings',
            ),
            child: Text(
              access == LocationAccess.serviceOff ? 'เปิด GPS' : 'เปิดหน้าตั้งค่า',
            ),
          ),
        ],
      ),
    );
    _permissionDialogOpen = false;

    if (choice == 'settings') await LocationService.openSettings();
    if (choice == 'gps') await LocationService.openLocationSettings();
  }

  Future<void> _refreshOffices() async {
    try {
      await LocationService.refreshOfficesFromServer();
    } catch (err) {
      debugPrint('Using bundled geofence settings: $err');
    }
  }

  Future<void> _watchPositions() async {
    await _positionSub?.cancel();
    _positionSub = LocationService.stream().listen((pos) {
      if (!mounted) return;
      try {
        // รองรับหลายสถานที่ — เลือกที่ที่เข้าเขตแล้ว หรือที่ใกล้ที่สุดถ้ายังไม่เข้า
        final (office, dist, within) =
            LocationService.nearestOffice(pos.latitude, pos.longitude);
        final (workOffice, workDistance, withinWork) =
            LocationService.nearestOffice(
          pos.latitude,
          pos.longitude,
          workOnly: true,
        );
        setState(() {
          _pos = pos;
          _distanceKm = dist;
          _allowedRadiusKm = workOffice.radiusKm;
          _workDistanceKm = workDistance;
          _nearestOfficeName = workOffice.name;
          _within = within;
          _withinWork = withinWork;
          _status = within
              ? 'อยู่ในเขต ${office.name} พร้อมเช็คอิน'
              : 'อยู่นอกเขต — ใกล้สุดคือ ${office.name} '
                  'ห่าง ${dist.toStringAsFixed(2)} กม.';
        });
      } catch (err) {
        debugPrint('Cannot evaluate geofence: $err');
        setState(() {
          _pos = pos;
          _distanceKm = null;
          _allowedRadiusKm = null;
          _workDistanceKm = null;
          _nearestOfficeName = null;
          _within = false;
          _withinWork = false;
          _status = 'ยังไม่ได้กำหนดสถานที่ทำงานสำหรับออกงาน';
        });
      }
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _status = 'ไม่สามารถอ่านตำแหน่งได้');
    });
  }

  // -------------------------------------------------------------------
  // การลงเวลาของวันนี้
  // -------------------------------------------------------------------
  Future<void> _loadToday() async {
    if (!ApiService.isLoggedIn || !mounted) return;
    setState(() {
      _loadingToday = true;
      _todayError = null;
    });
    try {
      final data = await AttendanceService.today();
      if (!mounted) return;
      setState(() {
        _today = data;
        _loadingToday = false;
      });
    } catch (err) {
      debugPrint('Load today attendance failed: $err');
      if (!mounted) return;
      setState(() {
        _loadingToday = false;
        _todayError = 'โหลดรายการลงเวลาไม่สำเร็จ '
            'ตรวจอินเทอร์เน็ตแล้วกดโหลดใหม่อีกครั้ง';
      });
    }
  }

  Future<void> _refreshAll() async {
    await _setupTracking();
    await _loadToday();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _permissionNagTimer?.cancel();
    _attendanceTimer?.cancel();
    _clockTimer?.cancel();
    _positionSub?.cancel();
    _trackingSub?.cancel();
    super.dispose();
  }

  Future<void> _goCheckIn(String kind) async {
    if (_pos == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => CheckInScreen(
          kind: kind,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(kind == 'in' ? 'เข้างานสำเร็จ' : 'ออกงานสำเร็จ')),
      );
      // ลงเวลาเสร็จแล้ว รายการของวันนี้ต้องขึ้นทันที ไม่ต้องรอรอบรีเฟรช
      await _loadToday();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _within ? Colors.green : Colors.orange;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo-checkin.png',
              width: 34,
              height: 34,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text('เช็คอินเข้างาน'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: color.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(_within ? Icons.check_circle : Icons.location_off,
                        size: 56, color: color),
                    const SizedBox(height: 10),
                    Text(_status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    if (_pos != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'พิกัด: ${_pos!.latitude.toStringAsFixed(5)}, '
                        '${_pos!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      Text(
                          'ห่างออฟฟิศ '
                          '${_distanceKm?.toStringAsFixed(2) ?? '-'} กม.',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TrackingStatusCard(
              access: _access,
              serviceRunning: _trackingRunning,
              preparing: _preparingTracking,
              lastPingAt: _lastPingAt,
              onGrant: () => _setupTracking(promptIfMissing: true),
              onOpenSettings: LocationService.openSettings,
              onOpenGps: LocationService.openLocationSettings,
            ),
            const SizedBox(height: 12),
            TodayAttendanceCard(
              attendance: _today,
              loading: _loadingToday,
              error: _todayError,
              onRefresh: _loadToday,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _within ? () => _goCheckIn('in') : null,
              icon: const Icon(Icons.login),
              label: const Text('เข้างาน (สแกนหน้า)'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _withinWork ? () => _goCheckIn('out') : null,
              icon: const Icon(Icons.logout),
              label: const Text('ออกงาน (สแกนหน้า)'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            if (_pos != null && !_withinWork) ...[
              const SizedBox(height: 10),
              Text(
                'ไม่สามารถออกงานได้ ต้องอยู่ภายในรัศมี '
                '${_allowedRadiusKm?.toStringAsFixed(2) ?? '-'} กม. '
                'ของ ${_nearestOfficeName ?? 'สถานที่ทำงาน'} '
                '(ขณะนี้ห่าง ${_workDistanceKm?.toStringAsFixed(2) ?? '-'} กม.)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'ระบบจะตรวจ GPS อีกครั้งตอนกดยืนยัน ต้องอยู่ในเขตที่กำหนดและสแกนใบหน้าผ่าน จึงจะเข้างานหรือออกงานได้',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
