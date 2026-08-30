import 'dart:io';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'api_service.dart';

/// ระดับสิทธิ์ตำแหน่งที่แอปได้รับอยู่ตอนนี้
enum LocationAccess {
  /// ปิดบริการตำแหน่งไว้ทั้งเครื่อง — ขอสิทธิ์ไปก็ยังอ่านพิกัดไม่ได้
  serviceOff,

  /// ไม่อนุญาตให้เข้าถึงตำแหน่ง
  denied,

  /// ปฏิเสธถาวร (กด "ไม่อนุญาต" จนระบบไม่ถามอีก) ต้องไปเปิดเองในหน้าตั้งค่า
  deniedForever,

  /// อนุญาตเฉพาะตอนเปิดแอปอยู่ — ติดตามต่อเนื่องได้ไม่แน่นอน
  whileInUse,

  /// อนุญาตตลอดเวลา = ระดับที่ระบบนี้ต้องการ
  always,
}

extension LocationAccessInfo on LocationAccess {
  /// พอจะอ่านพิกัดได้ไหม (ยังไม่ถึงขั้น "ตลอดเวลา" ก็ยังส่ง ping ได้ตอนแอปเปิด)
  bool get canTrack =>
      this == LocationAccess.whileInUse || this == LocationAccess.always;

  /// ติดตามได้ต่อเนื่องแม้ปิดหน้าจอ/สลับไปแอปอื่น
  bool get isAlways => this == LocationAccess.always;

  /// แก้ในแอปไม่ได้แล้ว ต้องพาผู้ใช้ไปหน้าตั้งค่าของระบบ
  bool get needsSettings =>
      this == LocationAccess.deniedForever || this == LocationAccess.whileInUse;

  String get message {
    switch (this) {
      case LocationAccess.serviceOff:
        return 'ปิดบริการตำแหน่ง (GPS) อยู่ กรุณาเปิดเพื่อให้ระบบติดตามการเข้างานได้';
      case LocationAccess.denied:
        return 'ยังไม่ได้อนุญาตให้เข้าถึงตำแหน่ง กรุณากดอนุญาต';
      case LocationAccess.deniedForever:
        return 'ปิดสิทธิ์ตำแหน่งไว้ถาวร กรุณาเปิดในหน้าตั้งค่าแอป';
      case LocationAccess.whileInUse:
        return 'อนุญาตเฉพาะตอนเปิดแอป — ต้องเปลี่ยนเป็น "อนุญาตตลอดเวลา" '
            'ระบบจึงจะติดตามตำแหน่งได้จนกว่าจะออกจากระบบ';
      case LocationAccess.always:
        return 'อนุญาตตำแหน่งตลอดเวลาแล้ว';
    }
  }
}

class LocationService {
  static List<Office> _offices = Config.offices;

  static List<Office> get offices => List.unmodifiable(_offices);

  /// ระดับสิทธิ์ตอนนี้ — อ่านอย่างเดียว ไม่เด้งป๊อปอัปขอสิทธิ์
  static Future<LocationAccess> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _fromPermission(await Geolocator.checkPermission());
  }

  /// ขอสิทธิ์ขั้นแรก (ระหว่างใช้แอป) — ต้องผ่านขั้นนี้ก่อนถึงจะขอ "ตลอดเวลา" ได้
  static Future<LocationAccess> requestWhileInUse() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return _fromPermission(perm);
  }

  /// ขอสิทธิ์ "อนุญาตตลอดเวลา" (background location)
  ///
  /// Android 11 ขึ้นไปเลือกตัวเลือกนี้จากป๊อปอัปตรงๆ ไม่ได้ ระบบบังคับให้ไป
  /// กดเองในหน้าตั้งค่าแอป ถ้าขอแล้วยังไม่ได้ ให้ฝั่งหน้าจอพาไป openSettings()
  static Future<LocationAccess> requestAlways() async {
    final base = await requestWhileInUse();
    if (!base.canTrack) return base;
    if (base.isAlways) return base;

    final status = await Permission.locationAlways.request();
    if (status.isGranted) return LocationAccess.always;
    return check();
  }

  /// ขอยกเว้นการประหยัดแบตให้แอปนี้ (Android)
  ///
  /// ไม่ขอก็ยังทำงานได้ แต่ระบบประหยัดแบตของเครื่องหลายรุ่นจะฆ่า service
  /// เบื้องหลังทิ้ง ทำให้พิกัดขาดหายเป็นช่วงๆ — ล้มเหลวได้ ไม่ต้องบล็อกอะไร
  static Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return;
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      // เครื่องบางรุ่นไม่มีหน้านี้ — ข้ามไป
    }
  }

  /// หน้าตั้งค่าสิทธิ์ของแอป (ไว้ให้ผู้ใช้เลือก "อนุญาตตลอดเวลา" เอง)
  static Future<void> openSettings() => openAppSettings();

  /// หน้าตั้งค่าบริการตำแหน่งของเครื่อง (ไว้เปิด GPS)
  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static LocationAccess _fromPermission(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.always:
        return LocationAccess.always;
      case LocationPermission.whileInUse:
        return LocationAccess.whileInUse;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  }

  /// ของเดิม — ยังมีโค้ดส่วนอื่นเรียกใช้อยู่: อ่านพิกัดได้หรือยัง
  static Future<bool> ensurePermission() async =>
      (await requestWhileInUse()).canTrack;

  static Future<Position> current() {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// สตรีมพิกัดต่อเนื่อง (เปิด GPS ตลอดเวลา)
  static Stream<Position> stream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  static Future<void> refreshOfficesFromServer() async {
    final latest = await ApiService.fetchOffices();
    if (latest.isNotEmpty) {
      _offices = latest;
    }
  }

  /// ระยะทางจากออฟฟิศ (กม.) ด้วยสูตร Haversine
  /// ระยะทางระหว่างสองพิกัด (กม.) ด้วยสูตร Haversine
  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final p1 = _rad(lat1), p2 = _rad(lat2);
    final dPhi = _rad(lat2 - lat1);
    final dLambda = _rad(lng2 - lng1);
    final a =
        pow(sin(dPhi / 2), 2) + cos(p1) * cos(p2) * pow(sin(dLambda / 2), 2);
    return 2 * r * asin(sqrt(a.toDouble()));
  }

  /// หาสถานที่ที่ "เข้าเขตแล้ว" ก่อน ถ้าไม่เข้าเลยก็เอาที่ใกล้ที่สุด
  /// คืน (สถานที่, ระยะทาง กม., อยู่ในเขตหรือไม่)
  static (Office, double, bool) nearestOffice(
    double lat,
    double lng, {
    bool workOnly = false,
  }) {
    Office? best;
    double bestDist = double.infinity;
    bool bestInside = false;

    final offices =
        workOnly ? _offices.where((office) => office.isWorkplace) : _offices;
    for (final o in offices) {
      final d = _haversineKm(lat, lng, o.lat, o.lng);
      final inside = d <= o.radiusKm;
      // เลือกที่อยู่ในเขตก่อนเสมอ ถ้าสถานะเท่ากันค่อยดูว่าใกล้กว่า
      final better = best == null ||
          (inside && !bestInside) ||
          (inside == bestInside && d < bestDist);
      if (better) {
        best = o;
        bestDist = d;
        bestInside = inside;
      }
    }
    if (best == null) {
      throw StateError('ยังไม่ได้กำหนดสถานที่ทำงานสำหรับการออกงาน');
    }
    return (best, bestDist, bestInside);
  }

  /// ระยะระหว่างสองพิกัด (กม.) — ให้หน้าจออื่นเรียกใช้ได้ เช่น รายการสถานที่
  static double distanceBetweenKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) =>
      _haversineKm(lat1, lng1, lat2, lng2);

  /// ตอนนี้อยู่ในเขต "บ้าน" หรือไม่
  ///
  /// อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่ต้องมีเข้างาน/ออกงาน — ดู README หัวข้อ "อยู่บ้าน"
  static bool insideHome(double lat, double lng) => _offices.any(
        (office) =>
            office.isHome &&
            _haversineKm(lat, lng, office.lat, office.lng) <= office.radiusKm,
      );

  /// ชื่อสถานที่ที่บันทึกไว้ในประวัติ เป็น "บ้าน" หรือไม่
  ///
  /// ประวัติเก็บแค่ชื่อ จึงเทียบกับรายการสถานที่ก่อน (ได้ category ที่ถูกต้อง)
  /// ถ้าไม่เจอ (สถานที่ถูกลบ/เปลี่ยนชื่อไปแล้ว) ค่อยเดาจากชื่อ
  static bool isHomeName(String? officeName) {
    final target = (officeName ?? '').trim();
    if (target.isEmpty) return false;
    for (final office in _offices) {
      if (office.name.trim() == target) return office.isHome;
    }
    return Office.isHomeLabel(target);
  }

  /// ระยะจากสถานที่ที่ใกล้ที่สุด (กม.)
  static double distanceFromOfficeKm(double lat, double lng) =>
      nearestOffice(lat, lng).$2;

  /// อยู่ในเขตของสถานที่ใดสถานที่หนึ่งหรือไม่
  static bool withinGeofence(double lat, double lng) =>
      nearestOffice(lat, lng).$3;

  static double _rad(double deg) => deg * pi / 180;
}
