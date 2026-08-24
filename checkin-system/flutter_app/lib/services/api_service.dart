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
  static DateTime? _sessionEndsAt;
  static const Duration _requestTimeout = Duration(seconds: 30);

  static const String _tokenKey = 'token';
  static const String _sessionEndKey = 'session_ends_at';

  /// ตอนเปิดแอปพบว่า session ที่ค้างอยู่หมดเวลาแล้ว จึงล้างทิ้ง
  /// หน้าล็อกอินเอาไปขึ้นข้อความบอกเหตุผล พนักงานจะได้ไม่งงว่าทำไมหลุด
  static bool sessionExpiredOnStart = false;

  /// เวลาหมดอายุรอบถัดไป = 4 ทุ่มของวันนี้ (เวลาไทย)
  /// ถ้าตอนนี้เลย 4 ทุ่มไปแล้วก็เป็น 4 ทุ่มของวันพรุ่งนี้
  static DateTime nextSessionEnd([DateTime? from]) {
    // เลื่อนเป็นเวลาไทยก่อน แล้วค่อยเลื่อนกลับ — จะได้ไม่ขึ้นกับ timezone ของเครื่อง
    final nowTh = (from ?? DateTime.now()).toUtc().add(Config.thaiUtcOffset);
    var endTh = DateTime.utc(
      nowTh.year,
      nowTh.month,
      nowTh.day,
      Config.sessionEndHour,
      Config.sessionEndMinute,
    );
    if (!endTh.isAfter(nowTh)) endTh = endTh.add(const Duration(days: 1));
    return endTh.subtract(Config.thaiUtcOffset).toLocal();
  }

  static DateTime? get sessionEndsAt => _sessionEndsAt;

  /// เหลือเวลาใช้งานอีกเท่าไร — null = ยังไม่ได้ล็อกอิน
  /// ค่าติดลบหรือศูนย์ = หมดเวลาแล้ว
  static Duration? get timeLeftInSession {
    final endsAt = _sessionEndsAt;
    if (_token == null || endsAt == null) return null;
    return endsAt.difference(DateTime.now());
  }

  /// ล็อกอินอยู่ก็จริง แต่เลย 4 ทุ่มมาแล้ว
  static bool get isSessionExpired {
    final endsAt = _sessionEndsAt;
    if (_token == null) return false;
    return endsAt == null || !DateTime.now().isBefore(endsAt);
  }

  /// เรียกก่อนยิง API ทุกครั้ง — คืน false แปลว่าโดนเด้งออกไปแล้ว
  static Future<bool> ensureSession() async {
    if (_token == null) return false;
    if (!isSessionExpired) return true;
    await logout();
    return false;
  }

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);

    final raw = prefs.getString(_sessionEndKey);
    _sessionEndsAt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();

    // token เก่าที่ยังไม่มีเวลาหมดอายุ (ติดตั้งทับจากเวอร์ชันก่อนหน้า)
    // ถือว่าหมดแล้ว ให้ล็อกอินใหม่หนึ่งครั้ง จะได้เข้าเงื่อนไข 4 ทุ่มเหมือนกันทุกเครื่อง
    if (isSessionExpired) {
      sessionExpiredOnStart = true;
      await logout();
    }
  }

  static Future<void> _saveToken(String token) async {
    final endsAt = nextSessionEnd();
    _token = token;
    _sessionEndsAt = endsAt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_sessionEndKey, endsAt.toUtc().toIso8601String());
  }

  static bool get isLoggedIn => _token != null && !isSessionExpired;

  static Future<void> logout() async {
    _token = null;
    _sessionEndsAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_sessionEndKey);
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
    // isolate ของ background service ไม่ได้ผ่านหน้าจอเลย ต้องเช็กเวลาเองด้วย
    // ไม่งั้นเครื่องที่ลืมปิดจะส่งพิกัดต่อทั้งคืน
    if (!await ensureSession()) return;
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
    if (!await ensureSession()) {
      return const CheckInResult(
        success: false,
        message: Config.sessionExpiredMessage,
      );
    }

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
