import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class CheckInResult {
  final bool success;
  final String message;
  final String? kind;
  final DateTime? timestamp;
  final double? distanceKm;
  final String? officeName;

  const CheckInResult({
    required this.success,
    required this.message,
    this.kind,
    this.timestamp,
    this.distanceKm,
    this.officeName,
  });
}

class ApiService {
  static String? _token;
  static const Duration _requestTimeout = Duration(seconds: 30);

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static bool get isLoggedIn => _token != null;

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  // header พื้นฐาน: ข้ามหน้าเตือนของ ngrok (ไม่มีผลถ้าไม่ได้ใช้ ngrok)
  static const Map<String, String> _commonHeaders = {
    'ngrok-skip-browser-warning': 'true',
  };

  static Map<String, String> get _authHeaders =>
      {..._commonHeaders, 'Authorization': 'Bearer $_token'};

  static DateTime? parseServerTimestamp(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    // Backend stores timestamps in UTC, but older responses omit the timezone.
    // Treat timezone-less API timestamps as UTC before the UI converts to local.
    final hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    return DateTime.tryParse(hasTimezone ? text : '${text}Z');
  }

  /// เข้าสู่ระบบ (username = รหัสพนักงานหรืออีเมล)
  static Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/auth/login'),
      headers: {
        ..._commonHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'username': username, 'password': password},
    ).timeout(_requestTimeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await _saveToken(data['access_token']);
      return true;
    }
    return false;
  }

  /// ส่งพิกัด GPS ต่อเนื่อง (background)
  static Future<void> sendPing(double lat, double lng) async {
    if (_token == null) return;
    await http
        .post(
          Uri.parse('${Config.apiBase}/locations/ping'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'latitude': lat, 'longitude': lng}),
        )
        .timeout(_requestTimeout);
  }

  /// อ่านเงื่อนไข geofence จาก backend เพื่อให้แอปตรงกับ OFFICES ล่าสุด
  static Future<List<Office>> fetchOffices() async {
    final res = await http
        .get(
          Uri.parse('${Config.apiBase}/reports/geofence'),
          headers: _commonHeaders,
        )
        .timeout(_requestTimeout);
    if (res.statusCode != 200) {
      throw HttpException('โหลดข้อมูลสถานที่ไม่สำเร็จ (${res.statusCode})');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rawOffices = data['offices'];
    if (rawOffices is List && rawOffices.isNotEmpty) {
      return rawOffices
          .whereType<Map<String, dynamic>>()
          .map(Office.fromJson)
          .toList(growable: false);
    }

    return [
      Office(
        name: data['office_name']?.toString() ?? '-',
        lat: (data['office_lat'] as num).toDouble(),
        lng: (data['office_lng'] as num).toDouble(),
        radiusKm: (data['radius_km'] as num).toDouble(),
      ),
    ];
  }

  /// เช็คอิน/เช็คเอาต์ พร้อมแนบรูปใบหน้า
  static Future<CheckInResult> checkIn({
    required double lat,
    required double lng,
    required String kind, // "in" หรือ "out"
    required bool faceDetected,
    File? photo,
  }) async {
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.apiBase}/checkins'),
      )
        ..headers.addAll(_authHeaders)
        ..fields['latitude'] = lat.toString()
        ..fields['longitude'] = lng.toString()
        ..fields['kind'] = kind
        ..fields['face_detected'] = faceDetected.toString();

      if (photo != null) {
        req.files.add(await http.MultipartFile.fromPath('photo', photo.path));
      }

      final streamed = await req.send().timeout(_requestTimeout);
      final res =
          await http.Response.fromStream(streamed).timeout(_requestTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final action = data['kind'] == 'out' ? 'ออกงาน' : 'เข้างาน';
        return CheckInResult(
          success: true,
          message: 'บันทึก$actionสำเร็จ',
          kind: data['kind']?.toString(),
          timestamp: parseServerTimestamp(data['timestamp']),
          distanceKm: (data['distance_km'] as num?)?.toDouble(),
          officeName: data['office_name']?.toString(),
        );
      }
      try {
        final err = jsonDecode(res.body);
        final detail = err is Map ? err['detail'] : null;
        return CheckInResult(
          success: false,
          message: detail?.toString() ?? 'เกิดข้อผิดพลาด',
        );
      } catch (_) {
        return CheckInResult(
          success: false,
          message: 'เกิดข้อผิดพลาด (${res.statusCode})',
        );
      }
    } on TimeoutException {
      return const CheckInResult(
        success: false,
        message: 'เชื่อมต่อเซิร์ฟเวอร์นานเกินไป กรุณาลองใหม่',
      );
    } on SocketException {
      return const CheckInResult(
        success: false,
        message: 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจอินเทอร์เน็ต',
      );
    } catch (err) {
      return CheckInResult(
        success: false,
        message: 'บันทึกไม่สำเร็จ: $err',
      );
    }
  }
}
