import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/location_service.dart';
import 'checkin_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Position? _pos;
  double? _distanceKm;
  double? _allowedRadiusKm;
  double? _workDistanceKm;
  String? _nearestOfficeName;
  bool _within = false;
  bool _withinWork = false;
  String _status = 'กำลังหาตำแหน่ง...';
  StreamSubscription<Position>? _positionSub;
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch();
    _armSessionTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timer ไม่เดินตอนแอปถูกพักไว้ (หรือเครื่องดับไปทั้งคืน)
    // กลับมาเมื่อไหร่จึงต้องเทียบเวลาใหม่ทุกครั้ง
    if (state == AppLifecycleState.resumed) _armSessionTimer();
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

  Future<void> _watch() async {
    final ok = await LocationService.ensurePermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = 'กรุณาเปิด GPS และอนุญาตตำแหน่ง');
      return;
    }
    try {
      final serviceStarted = await initBackgroundService();
      if (!serviceStarted) {
        debugPrint(
            'Background service skipped: notification permission denied');
      }
    } catch (err) {
      debugPrint('Background service failed to start: $err');
    }
    try {
      await LocationService.refreshOfficesFromServer();
    } catch (err) {
      debugPrint('Using bundled geofence settings: $err');
    }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _positionSub?.cancel();
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
            onPressed: () async {
              await stopBackgroundService();
              await ApiService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Text('ห่างออฟฟิศ ${_distanceKm!.toStringAsFixed(2)} กม.',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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
            const Spacer(),
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
