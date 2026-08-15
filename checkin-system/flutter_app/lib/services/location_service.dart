import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../config.dart';

class LocationService {
  /// ขอสิทธิ์และตรวจว่า GPS เปิดอยู่
  static Future<bool> ensurePermission() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

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

  /// ระยะทางจากออฟฟิศ (กม.) ด้วยสูตร Haversine
  /// ระยะทางระหว่างสองพิกัด (กม.) ด้วยสูตร Haversine
  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final p1 = _rad(lat1), p2 = _rad(lat2);
    final dPhi = _rad(lat2 - lat1);
    final dLambda = _rad(lng2 - lng1);
    final a = pow(sin(dPhi / 2), 2) +
        cos(p1) * cos(p2) * pow(sin(dLambda / 2), 2);
    return 2 * r * asin(sqrt(a.toDouble()));
  }

  /// หาสถานที่ที่ "เข้าเขตแล้ว" ก่อน ถ้าไม่เข้าเลยก็เอาที่ใกล้ที่สุด
  /// คืน (สถานที่, ระยะทาง กม., อยู่ในเขตหรือไม่)
  static (Office, double, bool) nearestOffice(double lat, double lng) {
    Office? best;
    double bestDist = double.infinity;
    bool bestInside = false;

    for (final o in Config.offices) {
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
    return (best!, bestDist, bestInside);
  }

  /// ระยะจากสถานที่ที่ใกล้ที่สุด (กม.)
  static double distanceFromOfficeKm(double lat, double lng) =>
      nearestOffice(lat, lng).$2;

  /// อยู่ในเขตของสถานที่ใดสถานที่หนึ่งหรือไม่
  static bool withinGeofence(double lat, double lng) =>
      nearestOffice(lat, lng).$3;

  static double _rad(double deg) => deg * pi / 180;
}
