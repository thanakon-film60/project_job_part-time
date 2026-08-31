import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/camera.dart';
import '../models/directory.dart';
import '../models/employee.dart';
import '../models/json.dart';
import '../models/live_location.dart';
import '../models/team_calendar.dart';

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

/// ข้อผิดพลาดจาก API ที่พร้อมเอาไปแสดงบนหน้าจอได้เลย
///
/// backend ตอบ error เป็น {"detail": "ข้อความภาษาไทย"} เสมอ จึงดึงข้อความนั้น
/// ออกมาใช้ตรงๆ แทนที่จะโชว์รหัสสถานะเปล่าๆ ที่ผู้ใช้อ่านไม่รู้เรื่อง
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static String? _token;
  static EmployeeAccount? _account;
  static DateTime? _sessionEndsAt;
  static const Duration _requestTimeout = Duration(seconds: 30);

  static const String _tokenKey = 'token';
  static const String _accountKey = 'employee';
  static const String _sessionEndKey = 'session_ends_at';

  /// ตอนเปิดแอปพบว่า session ที่ค้างอยู่หมดเวลาแล้ว จึงล้างทิ้ง
  /// หน้าล็อกอินเอาไปขึ้นข้อความบอกเหตุผล พนักงานจะได้ไม่งงว่าทำไมหลุด
  static bool sessionExpiredOnStart = false;

  /// บัญชีที่ล็อกอินอยู่ — null เมื่อยังไม่ได้ล็อกอิน
  ///
  /// ตัวนี้คือสิ่งที่บอกว่าจะโชว์เมนูของหัวหน้าหรือของพนักงาน
  static EmployeeAccount? get account => _account;

  /// ล็อกอินอยู่ด้วยบัญชีหัวหน้าหรือไม่
  ///
  /// เป็นแค่การซ่อน/แสดงเมนูเท่านั้น ตัวตัดสินจริงคือ backend ที่กัน
  /// endpoint ของหัวหน้าไว้ด้วย require_manager อยู่แล้ว
  static bool get isManager => _account?.isManager ?? false;

  /// เวลาหมดอายุรอบถัดไป = 4 ทุ่มของวันนี้ (เวลาไทย)
  /// ถ้าตอนนี้เลย 4 ทุ่มไปแล้วก็เป็น 4 ทุ่มของวันพรุ่งนี้
  static DateTime nextSessionEnd([DateTime? from]) {
    // เลื่อนเป็นเวลาไทยก่อน แล้วค่อยเลื่อนกลับ — จะได้ไม่ขึ้นกับ timezone ของเครื่อง
    final nowTh = Config.thaiNow(from);
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
    _account = _decodeAccount(prefs.getString(_accountKey));

    final raw = prefs.getString(_sessionEndKey);
    _sessionEndsAt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();

    // token เก่าที่ยังไม่มีเวลาหมดอายุ (ติดตั้งทับจากเวอร์ชันก่อนหน้า)
    // ถือว่าหมดแล้ว ให้ล็อกอินใหม่หนึ่งครั้ง จะได้เข้าเงื่อนไข 4 ทุ่มเหมือนกันทุกเครื่อง
    if (isSessionExpired) {
      sessionExpiredOnStart = true;
      await logout();
    }
  }

  static EmployeeAccount? _decodeAccount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      return EmployeeAccount.fromJson(data);
    } catch (_) {
      // ข้อมูลที่เก็บไว้เสีย — ถือว่ายังไม่รู้จักบัญชี แล้วให้ล็อกอินใหม่
      return null;
    }
  }

  static Future<void> _saveSession(
    String token,
    EmployeeAccount? account,
  ) async {
    final endsAt = nextSessionEnd();
    _token = token;
    _account = account;
    _sessionEndsAt = endsAt;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_sessionEndKey, endsAt.toUtc().toIso8601String());
    if (account == null) {
      await prefs.remove(_accountKey);
    } else {
      await prefs.setString(_accountKey, jsonEncode(account.toJson()));
    }
  }

  static bool get isLoggedIn => _token != null && !isSessionExpired;

  static Future<void> logout() async {
    _token = null;
    _account = null;
    _sessionEndsAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_accountKey);
    await prefs.remove(_sessionEndKey);
  }

  // header พื้นฐาน: ข้ามหน้าเตือนของ ngrok (ไม่มีผลถ้าไม่ได้ใช้ ngrok)
  static const Map<String, String> _commonHeaders = {
    'ngrok-skip-browser-warning': 'true',
  };

  static Map<String, String> get _authHeaders =>
      {..._commonHeaders, 'Authorization': 'Bearer $_token'};

  static DateTime? parseServerTimestamp(Object? value) =>
      parseServerDateTime(value);

  // -------------------------------------------------------------------
  // ตัวกลางเรียก API
  //
  // ทุกเส้นทางที่ต้องล็อกอินผ่านฟังก์ชันพวกนี้ทั้งหมด เพื่อให้เรื่องที่ต้อง
  // ทำเหมือนกันทุกครั้ง (เช็กเวลา 4 ทุ่ม, แนบ token, แปลง error ของ backend
  // เป็นข้อความไทย, เด้งออกเมื่อ 401) อยู่ที่เดียว ไม่ต้องเขียนซ้ำทุกเมธอด
  // -------------------------------------------------------------------

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${Config.apiBase}$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    if (!await ensureSession()) {
      throw const ApiException(Config.sessionExpiredMessage, statusCode: 401);
    }

    final uri = _uri(path, query);
    final headers = {
      ..._authHeaders,
      if (body != null) 'Content-Type': 'application/json',
    };
    final encoded = body == null ? null : jsonEncode(body);

    try {
      final Future<http.Response> request;
      switch (method) {
        case 'POST':
          request = http.post(uri, headers: headers, body: encoded);
        case 'PATCH':
          request = http.patch(uri, headers: headers, body: encoded);
        case 'PUT':
          request = http.put(uri, headers: headers, body: encoded);
        case 'DELETE':
          request = http.delete(uri, headers: headers);
        default:
          request = http.get(uri, headers: headers);
      }
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException('เชื่อมต่อเซิร์ฟเวอร์นานเกินไป กรุณาลองใหม่');
    } on SocketException {
      throw const ApiException(
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจอินเทอร์เน็ต',
      );
    }
  }

  /// ดึงข้อความ detail จาก body ของ error — backend ตอบเป็น {"detail": "..."}
  /// บางกรณี detail เป็น list ของ validation error ก็รวบเป็นบรรทัดเดียว
  static String _errorMessage(http.Response res, String fallback) {
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.trim().isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((item) => item is Map ? item['msg'] ?? item : item)
            .join('\n');
      }
    } catch (_) {
      // body ไม่ใช่ JSON (เช่นหน้า error ของ IIS) — ใช้ข้อความสำรอง
    }
    return '$fallback (${res.statusCode})';
  }

  static Future<dynamic> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    required String errorText,
  }) async {
    final res = await _send(method, path, query: query, body: body);

    if (res.statusCode == 401) {
      // token ถูกเพิกถอน/หมดอายุฝั่งเซิร์ฟเวอร์ — ล้างของในเครื่องให้ตรงกัน
      await logout();
      throw const ApiException(
        'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
        statusCode: 401,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        _errorMessage(res, errorText),
        statusCode: res.statusCode,
      );
    }

    // ต้องถอดรหัสเป็น utf8 เอง ไม่งั้นข้อความไทยจาก backend จะกลายเป็นตัวยึกยือ
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<List<Map<String, dynamic>>> _jsonList(
    String path, {
    Map<String, String>? query,
    required String errorText,
  }) async {
    final data = await _json('GET', path, query: query, errorText: errorText);
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  static Future<Map<String, dynamic>> _jsonMap(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    required String errorText,
  }) async {
    final data = await _json(
      method,
      path,
      query: query,
      body: body,
      errorText: errorText,
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException(errorText);
    }
    return data;
  }

  // -------------------------------------------------------------------
  // auth
  // -------------------------------------------------------------------

  /// เข้าสู่ระบบ (username = รหัสพนักงานหรืออีเมล)
  ///
  /// เก็บทั้ง token และข้อมูลบัญชี — ตัว is_manager ในนั้นคือสิ่งที่บอกว่า
  /// จะแสดงเมนูฝั่งหัวหน้าหรือไม่
  static Future<bool> login(String username, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {
        ..._commonHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'username': username, 'password': password},
    ).timeout(_requestTimeout);

    if (res.statusCode != 200) return false;

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final employee = data['employee'];
    await _saveSession(
      data['access_token'].toString(),
      employee is Map<String, dynamic>
          ? EmployeeAccount.fromJson(employee)
          : null,
    );
    return true;
  }

  // -------------------------------------------------------------------
  // ตำแหน่ง / geofence
  // -------------------------------------------------------------------

  /// ส่งพิกัด GPS ต่อเนื่อง (background)
  static Future<void> sendPing(double lat, double lng) async {
    // isolate ของ background service ไม่ได้ผ่านหน้าจอเลย ต้องเช็กเวลาเองด้วย
    // ไม่งั้นเครื่องที่ลืมปิดจะส่งพิกัดต่อทั้งคืน
    if (!await ensureSession()) return;
    await http
        .post(
          _uri('/locations/ping'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'latitude': lat, 'longitude': lng}),
        )
        .timeout(_requestTimeout);
  }

  /// อ่านเงื่อนไข geofence จาก backend เพื่อให้แอปตรงกับ OFFICES ล่าสุด
  static Future<List<Office>> fetchOffices() async {
    final res = await http
        .get(_uri('/reports/geofence'), headers: _commonHeaders)
        .timeout(_requestTimeout);
    if (res.statusCode != 200) {
      throw HttpException('โหลดข้อมูลสถานที่ไม่สำเร็จ (${res.statusCode})');
    }

    final data =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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

  /// ตำแหน่งล่าสุดของพนักงานทุกคน (หัวหน้าเท่านั้น)
  static Future<LiveLocationsSnapshot> fetchLiveLocations() async {
    return LiveLocationsSnapshot.fromJson(
      await _jsonMap(
        'GET',
        '/locations/live',
        errorText: 'โหลดตำแหน่งพนักงานไม่สำเร็จ',
      ),
    );
  }

  /// เส้นทางย้อนหลังของพนักงานหนึ่งคน (หัวหน้าเท่านั้น)
  static Future<List<TrailPoint>> fetchLocationTrail(
    int employeeId, {
    int hours = 6,
  }) async {
    final rows = await _jsonList(
      '/locations/trail/$employeeId',
      query: {'hours': '$hours'},
      errorText: 'โหลดเส้นทางย้อนหลังไม่สำเร็จ',
    );
    return rows.map(TrailPoint.fromJson).toList(growable: false);
  }

  // -------------------------------------------------------------------
  // การลงเวลา
  // -------------------------------------------------------------------

  /// ประวัติการลงเวลาของตัวเอง (JSON ดิบ — ให้ AttendanceService แปลงต่อ)
  ///
  /// [days] = ย้อนหลังกี่วันนับตามเวลาไทย, [limit] = จำกัดจำนวนรายการ
  /// เซิร์ฟเวอร์รุ่นเก่าที่ยังไม่รู้จักพารามิเตอร์นี้จะส่งมาทั้งหมด
  /// ไม่เป็นไร เพราะฝั่งแอปกรองเฉพาะวันที่ต้องการอยู่แล้ว
  static Future<List<Map<String, dynamic>>> fetchMyCheckIns({
    int days = 1,
    int limit = 200,
  }) {
    return _jsonList(
      '/checkins/me',
      query: {'days': '$days', 'limit': '$limit'},
      errorText: 'โหลดประวัติการลงเวลาไม่สำเร็จ',
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
    if (!await ensureSession()) {
      return const CheckInResult(
        success: false,
        message: Config.sessionExpiredMessage,
      );
    }

    try {
      final req = http.MultipartRequest('POST', _uri('/checkins'))
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
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
      return CheckInResult(
        success: false,
        message: _errorMessage(res, 'เกิดข้อผิดพลาด'),
      );
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

  // -------------------------------------------------------------------
  // รายงานสำหรับหัวหน้า
  // -------------------------------------------------------------------

  /// รายชื่อพนักงานทั้งหมดพร้อมแฟ้มประวัติ (หัวหน้าเท่านั้น)
  static Future<List<EmployeeProfile>> fetchEmployees() async {
    final rows = await _jsonList(
      '/reports/employees',
      errorText: 'โหลดข้อมูลพนักงานไม่สำเร็จ',
    );
    return rows.map(EmployeeProfile.fromJson).toList(growable: false);
  }

  /// ปฏิทินรวมของทีมในเดือนที่เลือก (หัวหน้าเท่านั้น)
  static Future<TeamCalendarMonth> fetchTeamCalendar(
    int year,
    int month,
  ) async {
    return TeamCalendarMonth.fromJson(
      await _jsonMap(
        'GET',
        '/reports/team-calendar',
        query: {'year': '$year', 'month': '$month'},
        errorText: 'โหลดปฏิทินทีมไม่สำเร็จ',
      ),
    );
  }

  /// ปฏิทินรายบุคคล (หัวหน้าเท่านั้น)
  static Future<EmployeeCalendarMonth> fetchEmployeeCalendar(
    int employeeId,
    int year,
    int month,
  ) async {
    return EmployeeCalendarMonth.fromJson(
      await _jsonMap(
        'GET',
        '/reports/calendar',
        query: {
          'employee_id': '$employeeId',
          'year': '$year',
          'month': '$month',
        },
        errorText: 'โหลดปฏิทินพนักงานไม่สำเร็จ',
      ),
    );
  }

  /// แฟ้มพนักงาน 1 คนในเดือนที่เลือก: ประวัติลงเวลา + รูปใบหน้า + timeline
  static Future<EmployeeHistory> fetchEmployeeHistory(
    int employeeId,
    int year,
    int month,
  ) async {
    return EmployeeHistory.fromJson(
      await _jsonMap(
        'GET',
        '/reports/employees/$employeeId/history',
        query: {'year': '$year', 'month': '$month'},
        errorText: 'โหลดประวัติพนักงานไม่สำเร็จ',
      ),
    );
  }

  // -------------------------------------------------------------------
  // แฟ้มพนักงาน (หัวหน้าเท่านั้น)
  // -------------------------------------------------------------------

  /// ค้นที่อยู่ไทยจากรหัสไปรษณีย์ 5 หลัก
  static Future<List<ThaiAddress>> fetchThaiAddresses(
    String postalCode,
  ) async {
    final rows = await _jsonList(
      '/addresses/postal-code/$postalCode',
      errorText: 'ค้นหาที่อยู่ไม่สำเร็จ',
    );
    return rows.map(ThaiAddress.fromJson).toList(growable: false);
  }

  /// แผนก/ตำแหน่งที่ระบบกำหนดไว้
  static Future<List<EmploymentOption>> fetchEmploymentOptions() async {
    final rows = await _jsonList(
      '/employment-options',
      errorText: 'โหลดแผนกและตำแหน่งไม่สำเร็จ',
    );
    return rows.map(EmploymentOption.fromJson).toList(growable: false);
  }

  /// เพิ่มแผนก/ตำแหน่งใหม่เข้ารายการ
  static Future<EmploymentOption> addEmploymentOption(
    String kind,
    String name,
  ) async {
    return EmploymentOption.fromJson(
      await _jsonMap(
        'POST',
        '/employment-options',
        body: {'kind': kind, 'name': name},
        errorText: 'เพิ่มตัวเลือกไม่สำเร็จ',
      ),
    );
  }

  /// ลงทะเบียนพนักงานใหม่ — คืนรหัสผ่านชั่วคราวมาให้ครั้งเดียว
  static Future<EmployeeRegistrationResult> registerEmployee(
    Map<String, dynamic> payload,
  ) async {
    return EmployeeRegistrationResult.fromJson(
      await _jsonMap(
        'POST',
        '/employee-management',
        body: payload,
        errorText: 'ลงทะเบียนพนักงานไม่สำเร็จ',
      ),
    );
  }

  /// แก้ไขแฟ้มพนักงาน — ส่งเฉพาะช่องที่เปลี่ยนจริง
  static Future<EmployeeProfile> updateEmployeeProfile(
    int employeeId,
    Map<String, dynamic> changes,
  ) async {
    return EmployeeProfile.fromJson(
      await _jsonMap(
        'PATCH',
        '/employee-management/$employeeId',
        body: changes,
        errorText: 'แก้ไขข้อมูลไม่สำเร็จ',
      ),
    );
  }

  // -------------------------------------------------------------------
  // ประวัติใบหน้า
  // -------------------------------------------------------------------

  /// รูปใบหน้าอ้างอิงของตัวเอง
  static Future<List<FaceRecord>> fetchMyFaces() async {
    final rows = await _jsonList(
      '/faces/me',
      errorText: 'โหลดประวัติใบหน้าไม่สำเร็จ',
    );
    return rows.map(FaceRecord.fromJson).toList(growable: false);
  }

  /// รูปใบหน้าของพนักงานคนหนึ่ง (เจ้าของหรือหัวหน้าเท่านั้น)
  static Future<List<FaceRecord>> fetchEmployeeFaces(int employeeId) async {
    final rows = await _jsonList(
      '/faces/employee/$employeeId',
      errorText: 'โหลดประวัติใบหน้าไม่สำเร็จ',
    );
    return rows.map(FaceRecord.fromJson).toList(growable: false);
  }

  /// จัดลำดับรูปใบหน้าของตัวเองใหม่ (ลากสลับในแอป)
  ///
  /// ต้องส่ง id ของรูป "ทุกใบ" มาพร้อมกัน — backend ปฏิเสธถ้าส่งไม่ครบ
  /// เพื่อไม่ให้เหลือรูปที่ลำดับค้างครึ่ง ๆ กลาง ๆ
  /// รูปแรกในลิสต์กลายเป็นรูปประจำตัวที่ใช้แสดงทุกที่
  static Future<List<FaceRecord>> reorderFaces(List<int> faceIds) async {
    final data = await _json(
      'PUT',
      '/faces/order',
      body: {'face_ids': faceIds},
      errorText: 'บันทึกลำดับรูปไม่สำเร็จ',
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(FaceRecord.fromJson)
        .toList(growable: false);
  }

  /// ลบรูปใบหน้าอ้างอิงทิ้ง (เจ้าของหรือหัวหน้า)
  ///
  /// ตอบ 204 ไม่มี body จึงอ่านผ่าน _json ไม่ได้ ต้องเช็กสถานะเอง
  static Future<void> deleteFace(int recordId) async {
    final res = await _send('DELETE', '/faces/$recordId');

    if (res.statusCode == 401) {
      await logout();
      throw const ApiException(
        'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
        statusCode: 401,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        _errorMessage(res, 'ลบรูปไม่สำเร็จ'),
        statusCode: res.statusCode,
      );
    }
  }

  /// ไฟล์รูปใบหน้า — ต้องแนบ token ไปด้วย จึงใช้ Image.network ตรงๆ ไม่ได้
  static Future<Uint8List> fetchFacePhoto(int recordId) async {
    final res = await _send('GET', '/faces/$recordId/photo');
    if (res.statusCode == 401) {
      await logout();
      throw const ApiException('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
          statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException(
        'โหลดรูปไม่สำเร็จ (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    return res.bodyBytes;
  }

  /// บันทึกรูปใบหน้าอ้างอิงเข้าประวัติของตัวเอง
  ///
  /// source = "mobile" เพื่อให้แยกออกจากรูปที่ถ่ายผ่านเว็บได้ในหน้าแฟ้มพนักงาน
  static Future<FaceRecord> enrollFace(File photo, {String? note}) async {
    if (!await ensureSession()) {
      throw const ApiException(Config.sessionExpiredMessage, statusCode: 401);
    }

    try {
      final req = http.MultipartRequest('POST', _uri('/faces/enroll'))
        ..headers.addAll(_authHeaders)
        ..fields['source'] = 'mobile';
      if (note != null && note.trim().isNotEmpty) {
        req.fields['note'] = note.trim();
      }
      req.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      final streamed = await req.send().timeout(_requestTimeout);
      final res =
          await http.Response.fromStream(streamed).timeout(_requestTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          _errorMessage(res, 'บันทึกใบหน้าไม่สำเร็จ'),
          statusCode: res.statusCode,
        );
      }
      return FaceRecord.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw const ApiException('บันทึกนานเกินไป กรุณาลองใหม่');
    } on SocketException {
      throw const ApiException(
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจอินเทอร์เน็ต',
      );
    }
  }

  // -------------------------------------------------------------------
  // เวอร์ชันแอป
  // -------------------------------------------------------------------

  /// ไฟล์ติดตั้งเวอร์ชันล่าสุดบนเซิร์ฟเวอร์ — ไม่ต้องล็อกอิน
  static Future<AppRelease> fetchAppRelease() async {
    try {
      final res = await http
          .get(_uri('/app/info'), headers: _commonHeaders)
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return const AppRelease(available: false);
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map<String, dynamic>) {
        return const AppRelease(available: false);
      }
      return AppRelease.fromJson(data);
    } catch (_) {
      // เช็กเวอร์ชันไม่ได้ไม่ใช่เรื่องคอขาดบาดตาย — แอปยังใช้งานได้ปกติ
      return const AppRelease(available: false);
    }
  }

  /// ลิงก์ดาวน์โหลดไฟล์ติดตั้ง (เปิดในเบราว์เซอร์)
  static String get appDownloadUrl => '${Config.apiBase}/app/download';

  // -------------------------------------------------------------------
  // กล้องวงจรปิด (หัวหน้าเท่านั้น)
  //
  // กล้องเป็น IP ในวง LAN ของออฟฟิศ แอปจึงไม่ได้คุยกับกล้องตรงๆ —
  // ทุกอย่างวิ่งผ่าน backend ที่อยู่วงเดียวกับกล้อง แปลว่าไม่ต้องเปิดพอร์ต
  // กล้องออกอินเทอร์เน็ต และภาพก็ถูกกันด้วย token เหมือน endpoint อื่น
  // -------------------------------------------------------------------

  /// เซิร์ฟเวอร์ต่อกล้องติดไหม + รุ่น/เฟิร์มแวร์
  static Future<CameraStatus> fetchCameraStatus() async {
    final data = await _jsonMap(
      'GET',
      '/camera/status',
      errorText: 'เช็คสถานะกล้องไม่สำเร็จ',
    );
    return CameraStatus.fromJson(data);
  }

  /// สั่งกล้องหมุน 1 จังหวะ
  ///
  /// เซิร์ฟเวอร์เป็นคนสั่งหยุดให้เองเมื่อครบเวลา แอปไม่ต้องส่ง stop ตามมา —
  /// ถ้าเน็ตมือถือหลุดกลางทาง กล้องจะได้ไม่หมุนค้าง
  static Future<void> moveCamera(String action, {int? durationMs}) async {
    await _jsonMap(
      'POST',
      '/camera/ptz',
      body: {
        'action': action,
        if (durationMs != null) 'duration_ms': durationMs,
      },
      errorText: 'สั่งกล้องไม่สำเร็จ',
    );
  }

  /// ปุ่มฉุกเฉิน — สั่งกล้องหยุดทันที
  static Future<void> stopCamera() async {
    await _jsonMap(
      'POST',
      '/camera/ptz/stop',
      errorText: 'สั่งหยุดกล้องไม่สำเร็จ',
    );
  }

  /// ภาพนิ่งล่าสุดจากกล้อง — ต้องแนบ token จึงใช้ Image.network ตรงๆ ไม่ได้
  /// (เหมือน fetchFacePhoto) แอปเรียกซ้ำเป็นระยะเพื่อทำเป็นภาพสด
  static Future<Uint8List> fetchCameraSnapshot() async {
    final res = await _send('GET', '/camera/snapshot');
    if (res.statusCode == 401) {
      await logout();
      throw const ApiException(
        'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
        statusCode: 401,
      );
    }
    if (res.statusCode != 200) {
      throw ApiException(
        _errorMessage(res, 'โหลดภาพจากกล้องไม่สำเร็จ'),
        statusCode: res.statusCode,
      );
    }
    return res.bodyBytes;
  }
}
