import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import 'api_service.dart';

/// บริการ background ส่งพิกัด GPS ต่อเนื่องตลอดเวลา
/// เพื่อให้ระบบรู้ว่าพนักงานอยู่จุดไหน (อยู่ในเขตออฟฟิศหรือไม่)
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'mardodi_gps',
      initialNotificationTitle: 'MARDODI เช็คอิน',
      initialNotificationContent: 'กำลังติดตามตำแหน่งเพื่อการเข้างาน',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await ApiService.loadToken();

  Timer.periodic(
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
