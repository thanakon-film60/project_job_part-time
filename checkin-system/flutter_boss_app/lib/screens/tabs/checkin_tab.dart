import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../config.dart';
import '../../models/home_verification.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../services/home_verification_service.dart';
import '../../services/location_service.dart';
import '../../services/tracking_controller.dart';
import '../../services/work_schedule.dart';
import '../../widgets/duty_warning_card.dart';
import '../../widgets/home_verification_card.dart';
import '../../widgets/today_attendance_card.dart';
import '../../widgets/tracking_status_card.dart';
import '../checkin_screen.dart';
import '../home_verification_screen.dart';

/// แท็บหลัก — ตำแหน่งปัจจุบัน สถานะการติดตาม รายการลงเวลาวันนี้ และปุ่มลงเวลา
class CheckInTab extends StatefulWidget {
  final TrackingController tracking;

  const CheckInTab({super.key, required this.tracking});

  @override
  State<CheckInTab> createState() => _CheckInTabState();
}

class _CheckInTabState extends State<CheckInTab> {
  // ---- ตำแหน่งปัจจุบัน / geofence ----
  Position? _pos;
  double? _allowedRadiusKm;
  double? _workDistanceKm;
  String? _nearestOfficeName;
  bool _within = false;
  bool _withinWork = false;

  /// อยู่ในเขตบ้าน = ไม่ได้ไปทำงาน — ไม่มีเข้างาน/ออกงาน
  bool _atHome = false;
  String _status = 'กำลังหาตำแหน่ง...';
  StreamSubscription<Position>? _positionSub;

  // ---- การลงเวลาของวันนี้ ----
  DayAttendance? _today;
  bool _loadingToday = false;
  String? _todayError;

  // ---- ยืนยันตัวตนรายวันตอนอยู่บ้าน ----
  // บัญชีหัวหน้าก็ต้องสแกนเหมือนพนักงาน ไม่มีข้อยกเว้น
  // (ต่างจาก POST /checkins ที่ยกเว้นการตรวจใบหน้าให้ is_manager)
  HomeVerificationDay? _homeDay;
  // โหลดไม่สำเร็จ ≠ ยังไม่ได้ยืนยัน — ต้องแสดงว่า "ยังตรวจสอบผลไม่ได้"
  bool _homeDayFailed = false;
  // สาเหตุที่โหลดไม่สำเร็จ ใช้แยกข้อความ (เซิร์ฟเวอร์ยังไม่อัปเดต / เซสชันหมดอายุ / เน็ต)
  String? _homeDayFailureCode;
  bool _verifying = false;

  Timer? _attendanceTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    widget.tracking.addListener(_onTrackingChanged);
    _onTrackingChanged();
    _loadToday();
    _loadHomeDay();

    _attendanceTimer = Timer.periodic(
      Config.attendanceRefreshInterval,
      (_) => _loadToday(),
    );
    // เดินนาฬิกา "รวมเวลาทำงานวันนี้" และความสดของ ping
    _clockTimer = Timer.periodic(Config.workedClockTick, (_) {
      if (mounted) setState(() {});
    });
  }

  /// ได้สิทธิ์ตำแหน่งเมื่อไร ค่อยเริ่มอ่านพิกัดมาคิด geofence
  void _onTrackingChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.tracking.access.canTrack) {
      _watchPositions();
    } else {
      _positionSub?.cancel();
      _positionSub = null;
      setState(() => _status = widget.tracking.access.message);
    }
  }

  Future<void> _watchPositions() async {
    if (_positionSub != null) return; // ดูอยู่แล้ว ไม่ต้องเปิดสตรีมซ้ำ
    try {
      await LocationService.refreshOfficesFromServer();
    } catch (err) {
      debugPrint('Using bundled geofence settings: $err');
    }
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
        // อยู่ที่ทำงานถือว่ามาทำงานไว้ก่อน (เผื่อเขตบ้านซ้อนกับเขตที่ทำงาน)
        final atHome = !withinWork &&
            LocationService.insideHome(pos.latitude, pos.longitude);
        setState(() {
          _pos = pos;
          _allowedRadiusKm = workOffice.radiusKm;
          _workDistanceKm = workDistance;
          _nearestOfficeName = workOffice.name;
          _within = within;
          _withinWork = withinWork;
          _atHome = atHome;
          _status = atHome
              ? 'อยู่บ้าน — ไม่ได้ไปทำงาน'
              : within
                  ? 'อยู่ในเขต ${office.name} พร้อมเช็คอิน'
                  : 'อยู่นอกเขต — ใกล้สุดคือ ${office.name} '
                      'ห่าง ${dist.toStringAsFixed(2)} กม.';
        });
      } catch (err) {
        debugPrint('Cannot evaluate geofence: $err');
        setState(() {
          _pos = pos;
          _allowedRadiusKm = null;
          _workDistanceKm = null;
          _nearestOfficeName = null;
          _within = false;
          _withinWork = false;
          _atHome = false;
          _status = 'ยังไม่ได้กำหนดสถานที่ทำงานสำหรับออกงาน';
        });
      }
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _status = 'ไม่สามารถอ่านตำแหน่งได้');
    });
  }

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

  /// สถานะการยืนยันตัวตนของวันนี้ (ตัดวันด้วยเวลาไทยฝั่ง server)
  ///
  /// ล้มเหลวต้องขึ้น "ยังตรวจสอบผลไม่ได้" ไม่ใช่ "ยังไม่ได้ยืนยัน" เพราะ
  /// เน็ตหลุดไม่ใช่หลักฐานว่าผู้ใช้ไม่ได้รายงานตัว
  Future<void> _loadHomeDay() async {
    if (!ApiService.isLoggedIn || !mounted) return;
    try {
      final day = await HomeVerificationService.myDay();
      if (!mounted) return;
      setState(() {
        _homeDay = day;
        _homeDayFailed = false;
        _homeDayFailureCode = null;
      });
    } catch (err) {
      debugPrint('Load home verification failed: $err');
      if (!mounted) return;
      setState(() {
        _homeDayFailed = true;
        // เก็บสาเหตุไว้ให้การ์ดเลือกข้อความ — เน็ตหลุดกับเซิร์ฟเวอร์ยังไม่อัปเดต
        // ต้องบอกผู้ใช้คนละแบบ ไม่งั้นจะไล่แก้ผิดทาง
        _homeDayFailureCode = err is ApiException ? err.code : null;
      });
    }
  }

  Future<void> _goVerifyHome() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final result = await Navigator.of(context).push<HomeVerification>(
        MaterialPageRoute(builder: (_) => const HomeVerificationScreen()),
      );
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยืนยันตัวตนและรายงานสถานะแล้ว: อยู่บ้าน — ไม่ได้ไปทำงาน'),
          ),
        );
      }
      // โหลดใหม่เสมอ แม้ผู้ใช้กดยกเลิก เพราะอาจมีรายการที่กู้ผลได้ระหว่างทาง
      await _loadHomeDay();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _refreshAll() async {
    await widget.tracking.ensure();
    await _loadToday();
    await _loadHomeDay();
  }

  @override
  void dispose() {
    widget.tracking.removeListener(_onTrackingChanged);
    _attendanceTimer?.cancel();
    _clockTimer?.cancel();
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
      // ลงเวลาเสร็จแล้ว รายการของวันนี้ต้องขึ้นทันที ไม่ต้องรอรอบรีเฟรช
      await _loadToday();
      if (!mounted) return;

      // แจ้ง "สาย / ตรงเวลา" ทันทีที่ลงเวลาเสร็จ
      //
      // ยึดเวลาที่ backend บันทึกจริง (รายการที่เพิ่งโหลดมา) ไม่ใช่นาฬิกาในเครื่อง
      // เพื่อให้ข้อความตรงกับที่ส่งเข้ากลุ่ม LINE — เครื่องที่ตั้งเวลาผิดจะได้ไม่
      // เห็นคนละอย่างกับหัวหน้า ถ้ายังโหลดไม่ทันค่อยถอยไปใช้เวลาไทยตอนนี้
      final saved = _latestRecordOfKind(kind);
      final verdict = saved != null
          ? WorkScheduleService.evaluateRecord(saved)
          : WorkScheduleService.evaluate(
              kind: kind,
              thaiTime: Config.thaiNow(),
            );

      final base = kind == 'in' ? 'เข้างานสำเร็จ' : 'ออกงานสำเร็จ';
      messenger.showSnackBar(
        SnackBar(
          content: Text(verdict.applies ? '$base — ${verdict.label}' : base),
          backgroundColor: verdict.needsAttention ? Colors.deepOrange : null,
          // สายแล้วต้องอ่านทัน ให้ค้างนานกว่าปกติ
          duration: Duration(seconds: verdict.needsAttention ? 6 : 3),
        ),
      );
    }
  }

  /// รายการลงเวลาล่าสุดของวันนี้ที่เป็นชนิดเดียวกับที่เพิ่งกด (ข้ามรายการที่บ้าน)
  CheckInRecord? _latestRecordOfKind(String kind) {
    final records = _today?.workRecords ?? const <CheckInRecord>[];
    for (final record in records.reversed) {
      if (record.kind == kind) return record;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final color =
        _atHome ? Colors.indigo : (_within ? Colors.green : Colors.orange);
    // เข้างานไว้ที่ที่ทำงานแต่ยังไม่ได้กดออกงาน
    final openWork =
        _today?.sessions.where((session) => session.isOpen).firstOrNull;
    // ยังโหลดรายการของวันนี้ไม่เสร็จก็ยังไม่รู้ว่าลงเวลาแล้วหรือยัง — อย่าเพิ่งเตือน
    // แอปหัวหน้าไม่มีการลงทะเบียนใบหน้า เหลือเงื่อนไขเดียวคือวันนี้ลงเวลาหรือยัง
    final verification = DutyVerification(
      faceEnrolled: true,
      checkedInToday: _today == null ? true : !_today!.isEmpty,
    );
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ขึ้นก่อนทุกอย่าง — เป็นคำเตือนว่ายังไม่ได้รับผิดชอบต่อหน้าที่ของวันนี้
          if (verification.unverified) ...[
            DutyWarningCard(verification: verification),
            const SizedBox(height: 12),
          ],
          Card(
            color: color.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                      _atHome
                          ? Icons.home
                          : (_within ? Icons.check_circle : Icons.location_off),
                      size: 56,
                      color: color),
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
                    // ต้องเป็นระยะถึง "ที่ทำงาน" เสมอ ไม่ใช่สถานที่ใกล้สุดทุกประเภท
                    // (_distanceKm) — ตอนอยู่บ้าน ค่านั้นคือระยะถึงบ้าน แล้วป้าย
                    // "ห่างออฟฟิศ" จะอ่านผิดเป็นว่ายืนอยู่ข้างออฟฟิศ
                    Text(
                        'ห่าง ${_nearestOfficeName ?? 'ออฟฟิศ'} '
                        '${_workDistanceKm?.toStringAsFixed(2) ?? '-'} กม.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TrackingStatusCard(
            access: tracking.access,
            serviceRunning: tracking.running,
            preparing: tracking.preparing,
            lastPingAt: tracking.lastPingAt,
            onGrant: () => tracking.ensure(prompt: true),
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
          if (_atHome) ...[
            // อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่มีเข้างาน/ออกงาน
            // เหลือแค่บันทึกว่า "ถึงบ้านแล้ว" ให้หัวหน้ารู้ว่ากลับถึงบ้านแล้ว
            Card(
              color: Colors.indigo.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.home, color: Colors.indigo, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'อยู่บ้าน ไม่ต้องลงเวลาเข้า/ออกงาน',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'อยู่บ้านก็คืออยู่บ้าน — ไม่ได้ไปทำงาน จึงไม่นับเป็นเวลาทำงาน '
                      'และไม่มีออกงาน แต่ยังต้องเข้าสู่ระบบทุกวันเพื่อให้ระบบรู้ว่า '
                      'อยู่ที่ไหนและกำลังทำอะไร ระบบจะบันทึกตำแหน่งต่อเนื่อง '
                      'จนกว่าจะออกจากระบบ',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    if (openWork != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ยังค้างการเข้างานของวันนี้เมื่อ '
                              '${thaiClock(openWork.checkIn.timestamp)} น. '
                              'ต้องกดออกงานที่ที่ทำงาน กดที่บ้านไม่ได้',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ยืนยันตัวตนประจำวัน — สแกนใหม่ทุกรอบ ยืนยันซ้ำได้ตลอด
            // (ปุ่มเดิมปิดถาวรหลังมีรายการของวันนี้ ซึ่งขัดกับข้อกำหนดข้อ 7)
            HomeVerificationCard(
              day: _homeDay,
              loadFailed: _homeDayFailed,
              failureCode: _homeDayFailureCode,
              busy: _verifying,
              onVerify: _goVerifyHome,
              onRetryLoad: _loadHomeDay,
            ),
          ] else ...[
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
          ],
          const SizedBox(height: 20),
          Text(
            _atHome
                ? 'ระบบจะตรวจ GPS อีกครั้งตอนกดยืนยัน — การบันทึกว่าอยู่บ้าน '
                    'ไม่นับเป็นการเข้างาน และไม่ต้องกดออกงาน'
                : 'ระบบจะตรวจ GPS อีกครั้งตอนกดยืนยัน ต้องอยู่ในเขตที่กำหนดและสแกนใบหน้าผ่าน จึงจะเข้างานหรือออกงานได้',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
