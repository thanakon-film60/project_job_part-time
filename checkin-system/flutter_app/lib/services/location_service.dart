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
  static double distanceFromOfficeKm(double lat, double lng) {
    const r = 6371.0;
    final p1 = _rad(lat), p2 = _rad(Config.officeLat);
    final dPhi = _rad(Config.officeLat - lat);
    final dLambda = _rad(Config.officeLng - lng);
    final a = pow(sin(dPhi / 2), 2) +
        cos(p1) * cos(p2) * pow(sin(dLambda / 2), 2);
    return 2 * r * asin(sqrt(a.toDouble()));
  }

  static bool withinGeofence(double lat, double lng) =>
      distanceFromOfficeKm(lat, lng) <= Config.geofenceRadiusKm;

  static double _rad(double deg) => deg * pi / 180;
}
