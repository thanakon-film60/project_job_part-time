import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'api_service.dart';

/// บริการ background ส่งพิกัด GPS ต่อเนื่องตลอดเวลา
/// เพื่อให้ระบบรู้ว่าพนักงานอยู่จุดไหน (อยู่ในเขตออฟฟิศหรือไม่)
Future<bool> initBackgroundService() async {
  final canPostNotification = await _ensureNotificationPermission();
  if (!canPostNotification) return false;

  final service = FlutterBackgroundService();
  if (await service.isRunning()) return true;

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      initialNotificationTitle: 'MARDODI เช็คอิน',
      initialNotificationContent: 'กำลังติดตามตำแหน่งเพื่อการเข้างาน',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );

  await service.startService();
  return true;
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
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await ApiService.loadToken();

  Timer? pingTimer;
  service.on('stopService').listen((_) {
    pingTimer?.cancel();
    service.stopSelf();
  });

  pingTimer = Timer.periodic(
    const Duration(seconds: Config.pingIntervalSeconds),
    (timer) async {
      if (!ApiService.isLoggedIn) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await ApiService.sendPing(pos.latitude, pos.longitude);
      } catch (_) {
        // เงียบไว้ ครั้งหน้าลองใหม่
      }
    },
  );
}
