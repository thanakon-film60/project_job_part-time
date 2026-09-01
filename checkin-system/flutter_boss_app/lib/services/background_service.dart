import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'api_service.dart';

/// คีย์ใน SharedPreferences ที่ isolate เบื้องหลังใช้บอกหน้าจอว่าส่งพิกัดล่าสุดเมื่อไร
/// (แชร์ผ่านหน่วยความจำตรงๆ ไม่ได้ เพราะคนละ isolate กัน)
const String _lastPingKey = 'last_ping_at';
const String _lastPingErrorKey = 'last_ping_error';

/// สถานะการติดตามที่ isolate เบื้องหลังส่งกลับมาให้หน้าจอแบบเรียลไทม์
class TrackingUpdate {
  final DateTime? sentAt;
  final double? latitude;
  final double? longitude;
  final String? error;

  const TrackingUpdate({this.sentAt, this.latitude, this.longitude, this.error});

  bool get isError => error != null;

  factory TrackingUpdate.fromMap(Map<String, dynamic> map) {
    final raw = map['sent_at']?.toString();
    return TrackingUpdate(
      sentAt: raw == null ? null : DateTime.tryParse(raw)?.toLocal(),
      latitude: (map['lat'] as num?)?.toDouble(),
      longitude: (map['lng'] as num?)?.toDouble(),
      error: map['error']?.toString(),
    );
  }
}

/// บริการ background ส่งพิกัด GPS ต่อเนื่องตลอดเวลา
/// เพื่อให้ระบบรู้ว่าพนักงานอยู่จุดไหน (อยู่ในเขตออฟฟิศหรือไม่)
///
/// เริ่มทำงานตั้งแต่ล็อกอินสำเร็จ ไม่ว่าจะยังไม่ได้เช็คอิน อยู่บ้าน หรืออยู่นอกเขต
/// และหยุดเมื่อออกจากระบบ / ถูกเด้งออกตอน 4 ทุ่ม เท่านั้น
///
/// ต้องเรียก "หลัง" ได้สิทธิ์ตำแหน่งแล้วเสมอ — Android 14 ขึ้นไปจะไม่ยอมให้
/// สตาร์ต foreground service ชนิด location ถ้ายังไม่ได้สิทธิ์ตำแหน่ง
Future<bool> initBackgroundService() async {
  // ขอสิทธิ์แจ้งเตือนเพื่อให้เห็นแถบ "กำลังติดตามตำแหน่ง"
  // ไม่ได้ก็ไม่เป็นไร — service ยังรันต่อได้ แค่ผู้ใช้จะไม่เห็นแถบนั้น
  // (ของเดิมยกเลิกการติดตามทั้งหมดเมื่อไม่ได้สิทธิ์แจ้งเตือน ซึ่งแรงเกินไป)
  await _ensureNotificationPermission();

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    // รันอยู่แล้ว — สะกิดให้อ่าน token รอบใหม่ เผื่อเพิ่งล็อกอินด้วยบัญชีอื่น
    service.invoke('refreshSession');
    return true;
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      // เปิดเครื่องมาแล้วยังล็อกอินค้างอยู่ ให้กลับมาติดตามต่อเอง
      autoStartOnBoot: true,
      isForegroundMode: true,
      foregroundServiceTypes: const [AndroidForegroundType.location],
      initialNotificationTitle: 'THANAKON-BOX เช็คอิน',
      initialNotificationContent: 'กำลังติดตามตำแหน่งเพื่อการเข้างาน',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );

  return service.startService();
}

Future<bool> _ensureNotificationPermission() async {
  if (!Platform.isAndroid) return true;

  final status = await Permission.notification.status;
  if (status.isGranted) return true;
  if (status.isPermanentlyDenied || status.isRestricted) return false;

  final requested = await Permission.notification.request();
  return requested.isGranted;
}

Future<void> stopBackgroundService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stopService');
  }
  await _clearLastPing();
}

Future<bool> isTrackingRunning() => FlutterBackgroundService().isRunning();

/// ให้หน้าจอเกาะดูว่าเบื้องหลังส่งพิกัดไปแล้วหรือยัง
Stream<TrackingUpdate> trackingUpdates() => FlutterBackgroundService()
    .on('tracking')
    .where((event) => event != null)
    .map((event) => TrackingUpdate.fromMap(event!));

/// เวลาที่ส่งพิกัดสำเร็จครั้งล่าสุด — ใช้ตอนเปิดหน้าจอขึ้นมาใหม่
/// (ตอนนั้นยังไม่ทันได้ยิน event จาก isolate เบื้องหลัง)
Future<TrackingUpdate> lastTrackingUpdate() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(_lastPingKey);
  return TrackingUpdate(
    sentAt: raw == null ? null : DateTime.tryParse(raw)?.toLocal(),
    error: prefs.getString(_lastPingErrorKey),
  );
}

Future<void> _clearLastPing() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_lastPingKey);
  await prefs.remove(_lastPingErrorKey);
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await ApiService.loadToken();

  Timer? pingTimer;

  Future<void> stop() async {
    pingTimer?.cancel();
    pingTimer = null;
    await service.stopSelf();
  }

  service.on('stopService').listen((_) => stop());
  service.on('refreshSession').listen((_) => ApiService.loadToken());

  Future<void> report({
    DateTime? sentAt,
    Position? position,
    String? error,
  }) async {
    service.invoke('tracking', {
      'sent_at': (sentAt ?? DateTime.now()).toUtc().toIso8601String(),
      'lat': position?.latitude,
      'lng': position?.longitude,
      'error': error,
    });

    final prefs = await SharedPreferences.getInstance();
    if (error == null) {
      await prefs.setString(
        _lastPingKey,
        (sentAt ?? DateTime.now()).toUtc().toIso8601String(),
      );
      await prefs.remove(_lastPingErrorKey);
    } else {
      await prefs.setString(_lastPingErrorKey, error);
    }
  }

  Future<void> showNotification(String content) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'THANAKON-BOX กำลังติดตามตำแหน่ง',
        content: content,
      );
    }
  }

  Future<void> tick() async {
    // อ่าน token ใหม่ทุกรอบ — หน้าจอกับ background เป็นคนละ isolate
    // ถ้าเพิ่งล็อกอินใหม่/เพิ่งถูกเด้งออก ต้องรู้ตามภายในรอบเดียว
    await ApiService.loadToken();
    if (!ApiService.isLoggedIn) {
      // ออกจากระบบแล้ว หรือเลย 4 ทุ่ม — เลิกตามตำแหน่ง
      await _clearLastPing();
      await stop();
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 30));
      await ApiService.sendPing(pos.latitude, pos.longitude);
      final now = DateTime.now();
      await report(sentAt: now, position: pos);
      await showNotification(
        'ส่งพิกัดล่าสุด ${_clock(now)} น. — ติดตามจนกว่าจะออกจากระบบ',
      );
    } catch (err) {
      // เงียบไว้ ครั้งหน้าลองใหม่ แต่บอกหน้าจอ/แถบแจ้งเตือนว่าสะดุดอยู่
      await report(error: err.toString());
      await showNotification('ส่งพิกัดไม่สำเร็จ กำลังลองใหม่อัตโนมัติ');
    }
  }

  // ส่งทันที 1 ครั้ง ไม่ต้องรอครบนาทีแรก จะได้เห็นผลตั้งแต่เพิ่งล็อกอิน
  await tick();
  pingTimer = Timer.periodic(
    const Duration(seconds: Config.pingIntervalSeconds),
    (_) => tick(),
  );
}

String _clock(DateTime value) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(value.hour)}:${pad(value.minute)}';
}
