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

  /// เข้าสู่ระบบ (username = รหัสพนักงานหรืออีเมล)
  static Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/auth/login'),
      headers: {
        ..._commonHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'username': username, 'password': password},
    );
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
    await http.post(
      Uri.parse('${Config.apiBase}/locations/ping'),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'latitude': lat, 'longitude': lng}),
    );
  }

  /// เช็คอิน/เช็คเอาต์ พร้อมแนบรูปใบหน้า
  static Future<CheckInResult> checkIn({
    required double lat,
    required double lng,
    required String kind, // "in" หรือ "out"
    required bool faceDetected,
    File? photo,
  }) async {
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

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final action = data['kind'] == 'out' ? 'ออกงาน' : 'เข้างาน';
      return CheckInResult(
        success: true,
        message: 'บันทึก$actionสำเร็จ',
        kind: data['kind']?.toString(),
        timestamp: DateTime.tryParse(data['timestamp']?.toString() ?? ''),
        distanceKm: (data['distance_km'] as num?)?.toDouble(),
        officeName: data['office_name']?.toString(),
      );
    }
    try {
      final err = jsonDecode(res.body);
      return CheckInResult(
        success: false,
        message: err['detail']?.toString() ?? 'เกิดข้อผิดพลาด',
      );
    } catch (_) {
      return CheckInResult(
        success: false,
        message: 'เกิดข้อผิดพลาด (${res.statusCode})',
      );
    }
  }
}
