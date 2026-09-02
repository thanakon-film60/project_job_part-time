import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'background_service.dart';
import 'location_service.dart';

/// สถานะการติดตามตำแหน่งของทั้งแอป
///
/// อยู่ระดับเดียวกับ AppShell ไม่ใช่ระดับแท็บ เพราะการติดตามต้องเดินต่อ
/// ไม่ว่าตอนนั้นผู้ใช้จะเปิดแท็บไหนอยู่ — และต้องหยุดเมื่อออกจากระบบเท่านั้น
class TrackingController extends ChangeNotifier {
  LocationAccess _access = LocationAccess.denied;
  bool _running = false;
  bool _preparing = false;
  DateTime? _lastPingAt;
  double? _lastLatitude;
  double? _lastLongitude;
  bool _askedBatteryExemption = false;
  StreamSubscription<TrackingUpdate>? _updates;

  LocationAccess get access => _access;
  bool get running => _running;
  bool get preparing => _preparing;
  DateTime? get lastPingAt => _lastPingAt;
  double? get lastLatitude => _lastLatitude;
  double? get lastLongitude => _lastLongitude;

  /// ส่งพิกัดล่าสุดนานเกินไปแล้ว (ปิด GPS / เน็ตหลุด / ระบบฆ่า service)
  bool get isStale {
    final last = _lastPingAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > Config.trackingStaleAfter;
  }

  bool get isHealthy => _access.isAlways && _running && !isStale;

  /// ขอสิทธิ์ที่ยังขาด แล้วเปิดบริการติดตามให้พร้อมใช้งาน
  ///
  /// [prompt] = true ให้เด้งขอสิทธิ์กับผู้ใช้ได้ (ตอนเข้าแอป/ตอนกดปุ่ม/ตอนทวงซ้ำ)
  /// false = แค่อ่านสถานะปัจจุบันแล้วปรับให้ตรง (ตอนกลับเข้าแอป)
  Future<LocationAccess> ensure({bool prompt = false}) async {
    _preparing = true;
    notifyListeners();
    try {
      var access = prompt
          ? await LocationService.requestWhileInUse()
          : await LocationService.check();

      // ได้แค่ "ตอนเปิดแอป" ยังไม่พอ ต้องดัน "ตลอดเวลา" ต่อทุกครั้งที่มีโอกาส
      if (access.canTrack && !access.isAlways) {
        access = await LocationService.requestAlways();
      }
      _access = access;

      if (!access.canTrack) {
        await _stopService();
        return access;
      }

      // Android หลายรุ่นฆ่า service เบื้องหลังทิ้งเพราะโหมดประหยัดแบต — ขอยกเว้นครั้งเดียว
      if (prompt && !_askedBatteryExemption) {
        _askedBatteryExemption = true;
        await LocationService.requestBatteryExemption();
      }

      await _startService();
      return access;
    } finally {
      _preparing = false;
      notifyListeners();
    }
  }

  /// หยุดติดตาม — ใช้ตอนออกจากระบบ/หมดเวลาประจำวัน
  Future<void> stop() async {
    await _stopService();
    notifyListeners();
  }

  Future<void> _startService() async {
    try {
      final started = await initBackgroundService();
      _updates ??= trackingUpdates().listen((update) {
        _running = true;
        if (!update.isError) {
          _lastPingAt = update.sentAt;
          if (update.latitude != null && update.longitude != null) {
            _lastLatitude = update.latitude;
            _lastLongitude = update.longitude;
          }
        }
        notifyListeners();
      });
      _running = started && await isTrackingRunning();
      _lastPingAt = (await lastTrackingUpdate()).sentAt ?? _lastPingAt;
    } catch (err) {
      debugPrint('Background service failed to start: $err');
      _running = false;
    }
  }

  Future<void> _stopService() async {
    await stopBackgroundService();
    _running = false;
    _lastPingAt = null;
    _lastLatitude = null;
    _lastLongitude = null;
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }
}
