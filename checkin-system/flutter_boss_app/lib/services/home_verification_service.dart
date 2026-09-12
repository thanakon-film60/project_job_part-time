import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_verification.dart';
import 'api_service.dart';

/// ผลของการส่งหลักฐาน — แยก "ไม่รู้ผล" ออกจาก "ล้มเหลวแน่นอน"
///
/// เน็ตหลุดหลังส่งแล้ว **ห้ามบอกผู้ใช้ว่าล้มเหลว** เพราะ server อาจบันทึกไปแล้ว
/// ต้องกู้ผลด้วย request_id เดิมก่อน (ดู [recoverPending])
enum HomeVerifyOutcome { verified, rejected, unknown }

class HomeVerifyResult {
  final HomeVerifyOutcome outcome;
  final HomeVerification? verification;
  final String? message;

  /// รหัสสาเหตุจาก backend เมื่อถูกปฏิเสธ ใช้เลือกวิธีแก้ที่จะแสดง
  final String? code;

  const HomeVerifyResult._(this.outcome, {this.verification, this.message, this.code});

  factory HomeVerifyResult.verified(HomeVerification v) =>
      HomeVerifyResult._(HomeVerifyOutcome.verified, verification: v);

  factory HomeVerifyResult.rejected(String message, {String? code}) =>
      HomeVerifyResult._(HomeVerifyOutcome.rejected, message: message, code: code);

  factory HomeVerifyResult.unknown(String message) =>
      HomeVerifyResult._(HomeVerifyOutcome.unknown, message: message);

  bool get needsNewChallenge =>
      code == 'challenge_used' ||
      code == 'challenge_expired' ||
      code == 'challenge_invalid';

  bool get needsFaceEnrollment => code == 'face_not_enrolled';

  /// ต้องถ่ายรูปใหม่ ส่งรูปเดิมซ้ำไม่ได้
  bool get needsNewPhoto => code == 'evidence_reused' || code == 'evidence_invalid';

  bool get isOutsideHome => code == 'outside_home';
}

/// เรียก API ยืนยันตัวตนที่บ้าน + จำคำขอที่ยังไม่รู้ผล
///
/// ข้อกำหนด: DAILY_HOME_FACE_VERIFICATION_2026-09-11.md หัวข้อ 10
class HomeVerificationService {
  /// เก็บ request_id ที่ส่งไปแล้วแต่ยังไม่รู้ผล — ต้องอยู่รอดการปิด-เปิดแอป
  static const _pendingKey = 'home_verification_pending_request';

  static final _random = Random.secure();

  /// UUID v4 — ไม่ดึง package uuid เข้ามาเพิ่มเพราะใช้ที่เดียว
  static String newRequestId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // ---------------- คำขอที่ยังไม่รู้ผล ----------------

  static Future<void> _rememberPending(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, requestId);
  }

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  static Future<String?> pendingRequestId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingKey);
  }

  /// ตรวจคำขอที่ค้างอยู่ตอนเปิดหน้า — ใช้ตอนแอปถูกปิดกลางคันหลังส่ง
  ///
  /// คืน null = ยังไม่มีผล (อาจกำลังประมวลผล) ให้คงสถานะ "ยังตรวจสอบผลไม่ได้"
  /// **ไม่ลบ pending ทิ้งเมื่อหาไม่เจอ** เพราะไม่พบ ≠ ล้มเหลวแน่นอน
  static Future<HomeVerification?> recoverPending() async {
    final requestId = await pendingRequestId();
    if (requestId == null || requestId.isEmpty) return null;
    final found = await byRequestId(requestId);
    if (found != null) await clearPending();
    return found;
  }

  // ---------------- endpoint ----------------

  /// ขอโจทย์ใหม่ — ต้องเรียกทุกครั้งที่เริ่มยืนยันรอบใหม่
  static Future<HomeVerificationChallenge> requestChallenge() async {
    final data = await ApiService.postJson(
      '/home-verifications/challenges',
      errorText: 'ขอเริ่มการยืนยันตัวตนไม่สำเร็จ',
    );
    return HomeVerificationChallenge.fromJson(Map<String, dynamic>.from(data));
  }

  /// สถานะรายวันของตัวเอง (ไม่ส่ง date = วันนี้ตามเวลาไทยของ server)
  static Future<HomeVerificationDay> myDay({String? date}) async {
    final data = await ApiService.getJson(
      '/home-verifications/me',
      query: date == null ? null : {'date': date},
      errorText: 'โหลดสถานะการยืนยันไม่สำเร็จ',
    );
    return HomeVerificationDay.fromJson(Map<String, dynamic>.from(data));
  }

  /// สถานะรายวันของพนักงานคนหนึ่ง — เฉพาะบัญชีหัวหน้า
  static Future<HomeVerificationDay> employeeDay(int employeeId, {String? date}) async {
    final data = await ApiService.getJson(
      '/home-verifications/employee/$employeeId',
      query: date == null ? null : {'date': date},
      errorText: 'โหลดสถานะการยืนยันของพนักงานไม่สำเร็จ',
    );
    return HomeVerificationDay.fromJson(Map<String, dynamic>.from(data));
  }

  /// ตรวจผลคำขอเดิม — คืน null เมื่อ server ยังไม่มีผล (404)
  static Future<HomeVerification?> byRequestId(String requestId) async {
    try {
      final data = await ApiService.getJson(
        '/home-verifications/requests/$requestId',
        errorText: 'ตรวจผลการยืนยันไม่สำเร็จ',
      );
      return HomeVerification.fromJson(Map<String, dynamic>.from(data));
    } on ApiException catch (err) {
      if (err.statusCode == 404) return null;
      rethrow;
    }
  }

  /// ส่งหลักฐาน
  ///
  /// [requestId] ต้องเป็นค่าเดิมตลอดรอบการยืนยันหนึ่งครั้ง ถ้าส่งซ้ำด้วยค่าเดิม
  /// และเนื้อหาเดิม server จะคืนรายการเดิมให้ ไม่สร้างรายการใหม่
  static Future<HomeVerifyResult> submit({
    required String requestId,
    required String challengeId,
    required double latitude,
    required double longitude,
    required File photo,
    double? accuracyM,
  }) async {
    // จำไว้ก่อนยิง — ถ้าแอปถูกฆ่ากลางคันจะยังกู้ผลได้
    await _rememberPending(requestId);

    try {
      final res = await ApiService.postMultipart(
        '/home-verifications',
        fields: {
          'request_id': requestId,
          'challenge_id': challengeId,
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
          if (accuracyM != null) 'location_accuracy_m': accuracyM.toString(),
        },
        filePath: photo.path,
        fileField: 'photo',
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        await clearPending();
        return HomeVerifyResult.verified(HomeVerification.fromJson(data));
      }

      // server ตอบมาแล้วว่าไม่ผ่าน = รู้ผลแน่นอน ไม่ต้องกู้
      await clearPending();
      return HomeVerifyResult.rejected(
        ApiService.readErrorMessage(res, 'ยืนยันตัวตนไม่สำเร็จ'),
        code: ApiService.readErrorCode(res),
      );
    } on ApiException catch (err) {
      if (err.statusCode == 401) {
        await clearPending();
        return HomeVerifyResult.rejected(err.message, code: 'session_expired');
      }
      // ไม่ได้คำตอบจาก server — อาจบันทึกไปแล้ว ห้ามสรุปว่าล้มเหลว
      return HomeVerifyResult.unknown(
        'ยังตรวจสอบผลการยืนยันไม่ได้ — ${err.message}',
      );
    } catch (err) {
      return HomeVerifyResult.unknown('ยังตรวจสอบผลการยืนยันไม่ได้ ($err)');
    }
  }
}
