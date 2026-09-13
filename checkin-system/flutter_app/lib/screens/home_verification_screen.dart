import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/home_verification.dart';
import '../services/home_verification_service.dart';
import '../services/location_service.dart';
import '../widgets/face_scanner.dart';
import 'face_enroll_screen.dart';

/// หน้ายืนยันตัวตนว่า "อยู่บ้าน / ไม่ได้ไปทำงาน"
///
/// ข้อกำหนด: DAILY_HOME_FACE_VERIFICATION_2026-09-11.md หัวข้อ 10
///
/// สิ่งที่หน้านี้ **ไม่ทำ** โดยตั้งใจ: ไม่แสดงเวลาเข้า-ออก ไม่แสดงสถานะ
/// สาย/ตรงเวลา ไม่คิดชั่วโมงทำงาน — อยู่บ้านคือไม่ได้ไปทำงาน
///
/// ปิดหน้าแล้วคืนค่า [HomeVerification] เมื่อยืนยันสำเร็จ (null = ไม่สำเร็จ/ยกเลิก)
class HomeVerificationScreen extends StatefulWidget {
  const HomeVerificationScreen({super.key});

  @override
  State<HomeVerificationScreen> createState() => _HomeVerificationScreenState();
}

enum _Stage { preparing, scanning, submitting, blocked, resultUnknown }

class _HomeVerificationScreenState extends State<HomeVerificationScreen>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.preparing;
  HomeVerificationChallenge? _challenge;

  /// สร้างใหม่ทุกรอบการยืนยัน และคงค่าเดิมไว้จนกว่าจะรู้ผล
  String? _requestId;

  String _message = 'กำลังเตรียมการยืนยัน...';
  String? _hint;
  bool _needsEnrollment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // แอปถูกพักระหว่างสแกน — ทิ้งโจทย์รอบนี้แล้วเริ่มใหม่เมื่อกลับมา
    // แต่ถ้า "ส่งไปแล้ว" ห้ามยุ่ง เพราะ request_id ยังต้องใช้กู้ผล
    if (state == AppLifecycleState.paused && _stage == _Stage.scanning) {
      setState(() {
        _stage = _Stage.preparing;
        _challenge = null;
        _message = 'เริ่มการยืนยันใหม่หลังกลับเข้าแอป';
      });
    }
  }

  /// เริ่มรอบใหม่: กู้ผลค้าง → ขอโจทย์ใหม่ → ตรวจใบหน้าอ้างอิง
  Future<void> _start() async {
    setState(() {
      _stage = _Stage.preparing;
      _message = 'กำลังเตรียมการยืนยัน...';
      _hint = null;
      _needsEnrollment = false;
    });

    // มีคำขอค้างจากรอบก่อนที่ไม่รู้ผลหรือไม่ — ถ้าบันทึกไปแล้วถือว่าจบเลย
    try {
      final recovered = await HomeVerificationService.recoverPending();
      if (!mounted) return;
      if (recovered != null) {
        Navigator.of(context).pop(recovered);
        return;
      }
    } catch (_) {
      // กู้ไม่ได้ก็เริ่มรอบใหม่ตามปกติ — ไม่ใช่เหตุให้หยุดทั้งหน้า
    }

    try {
      final challenge = await HomeVerificationService.requestChallenge();
      if (!mounted) return;

      if (!challenge.faceEnrolled) {
        setState(() {
          _stage = _Stage.blocked;
          _needsEnrollment = true;
          _message = 'ยังไม่ได้ลงทะเบียนใบหน้า';
          _hint = 'ต้องมีใบหน้าอ้างอิงก่อน จึงจะยืนยันสถานะประจำวันได้';
        });
        return;
      }

      setState(() {
        _challenge = challenge;
        _requestId = HomeVerificationService.newRequestId();
        _stage = _Stage.scanning;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.blocked;
        _message = 'เริ่มการยืนยันไม่ได้';
        _hint = '$err';
      });
    }
  }

  Future<void> _goEnrollFace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FaceEnrollScreen()),
    );
    if (!mounted) return;
    _start();
  }

  /// ถ่ายรูปได้แล้ว — ตรวจพิกัดสดอีกครั้งแล้วส่ง
  ///
  /// คืน null = สำเร็จ (พาออกจากหน้าเอง) · คืนข้อความ = ให้ FaceScanner
  /// แสดงแล้วเปิดกล้องต่อให้ลองใหม่
  Future<String?> _onCapture(File photo) async {
    final challenge = _challenge;
    final requestId = _requestId;
    if (challenge == null || requestId == null) {
      return 'โจทย์การยืนยันหาย กรุณาเริ่มใหม่';
    }
    if (challenge.isExpired) {
      _restartForNewChallenge();
      return 'โจทย์หมดอายุแล้ว กำลังขอใหม่';
    }

    setState(() => _stage = _Stage.submitting);

    // ตรวจพิกัด ณ ตอนส่งจริง ไม่ใช้ค่าที่อ่านไว้ตอนเปิดหน้า
    // (server ตรวจซ้ำอีกชั้นอยู่แล้ว แต่ส่งค่าเก่าไปก็มีแต่จะโดนปฏิเสธเปล่า ๆ)
    final Position position;
    try {
      position = await LocationService.current();
    } catch (err) {
      if (!mounted) return null;
      setState(() => _stage = _Stage.scanning);
      return 'อ่านตำแหน่งไม่ได้ กรุณาเปิด GPS แล้วลองใหม่';
    }
    if (!mounted) return null;

    final result = await HomeVerificationService.submit(
      requestId: requestId,
      challengeId: challenge.challengeId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      photo: photo,
    );
    if (!mounted) return null;

    switch (result.outcome) {
      case HomeVerifyOutcome.verified:
        Navigator.of(context).pop(result.verification);
        return null;

      case HomeVerifyOutcome.unknown:
        // ส่งไปแล้วแต่ไม่ได้คำตอบ — อาจบันทึกแล้ว ห้ามบอกว่าล้มเหลว
        setState(() {
          _stage = _Stage.resultUnknown;
          _message = 'ยังตรวจสอบผลการยืนยันไม่ได้';
          _hint = result.message;
        });
        return null;

      case HomeVerifyOutcome.rejected:
        final message = result.message ?? 'ยืนยันตัวตนไม่สำเร็จ';
        if (result.needsFaceEnrollment) {
          setState(() {
            _stage = _Stage.blocked;
            _needsEnrollment = true;
            _message = 'ยังไม่ได้ลงทะเบียนใบหน้า';
            _hint = message;
          });
          return null;
        }
        if (result.isOutsideHome || result.code == 'session_expired') {
          setState(() {
            _stage = _Stage.blocked;
            _message = result.isOutsideHome
                ? 'ยืนยันสถานะที่บ้านไม่ได้'
                : 'เซสชันหมดอายุ';
            _hint = message;
          });
          return null;
        }
        if (result.needsNewChallenge) {
          _restartForNewChallenge();
          return '$message — กำลังเริ่มรอบใหม่';
        }
        // ถ่ายใหม่ได้เลยด้วยโจทย์เดิม (เช่นรูปใช้ไม่ได้) — แต่ต้องเป็นรูปใหม่
        setState(() => _stage = _Stage.scanning);
        return message;
    }
  }

  /// โจทย์ใช้ไม่ได้แล้ว — ต้องขอใหม่และสแกนใหม่ ห้ามใช้ของเดิมต่อ
  void _restartForNewChallenge() {
    setState(() {
      _challenge = null;
      _requestId = null;
    });
    _start();
  }

  /// ตรวจผลคำขอที่ยังไม่รู้ผล
  Future<void> _checkPendingResult() async {
    setState(() => _hint = 'กำลังตรวจผลคำขอเดิม...');
    try {
      final found = await HomeVerificationService.recoverPending();
      if (!mounted) return;
      if (found != null) {
        Navigator.of(context).pop(found);
        return;
      }
      setState(() => _hint =
          'ยังไม่พบผลของคำขอนี้ ระบบอาจกำลังบันทึกอยู่ — ลองตรวจอีกครั้งในอีกสักครู่ '
          'หรือกลับไปดูที่ประวัติของวันนี้');
    } catch (err) {
      if (!mounted) return;
      setState(() => _hint = 'ตรวจผลไม่สำเร็จ: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ยืนยันว่าอยู่บ้าน')),
      body: switch (_stage) {
        _Stage.scanning => _buildScanner(),
        _Stage.submitting => _buildBusy('กำลังยืนยันตัวตน...'),
        _Stage.preparing => _buildBusy(_message),
        _Stage.blocked => _buildBlocked(),
        _Stage.resultUnknown => _buildUnknown(),
      },
    );
  }

  Widget _buildScanner() {
    final action = _challenge?.action ?? 'หันหน้าตรงกล้อง';
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.indigo.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              const Text(
                'ทำตามคำสั่งนี้ขณะสแกน',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                action,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FaceScanner(
            confirmLabel: 'ยืนยันว่าอยู่บ้าน / ไม่ได้ไปทำงาน',
            onCapture: _onCapture,
            // ส่งคำสั่งจาก server ให้ scanner ตรวจว่าทำจริง ไม่ใช่แค่โชว์ข้อความ
            challengeAction: action,
            challengeCode: _challenge?.actionCode,
            footnote: 'ต้องสแกนใหม่ทุกครั้งที่ยืนยัน และต้องอยู่ในพื้นที่บ้านที่ระบบกำหนด\n'
                'การยืนยันนี้ไม่ใช่การเข้างาน จึงไม่มีเวลาเข้า–ออกและไม่คิดชั่วโมงทำงาน',
          ),
        ),
      ],
    );
  }

  Widget _buildBusy(String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _buildBlocked() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_hint != null) ...[
                const SizedBox(height: 8),
                Text(_hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 20),
              if (_needsEnrollment)
                FilledButton.icon(
                  onPressed: _goEnrollFace,
                  icon: const Icon(Icons.face),
                  label: const Text('ไปลงทะเบียนใบหน้า'),
                )
              else
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่'),
                ),
            ],
          ),
        ),
      );

  Widget _buildUnknown() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 56, color: Colors.blueGrey),
              const SizedBox(height: 12),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'คำขออาจถูกบันทึกไปแล้ว ระบบจะไม่สร้างรายการซ้ำ '
                'กรุณาตรวจผลก่อนเริ่มการยืนยันใหม่',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              if (_hint != null) ...[
                const SizedBox(height: 8),
                Text(_hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _checkPendingResult,
                icon: const Icon(Icons.search),
                label: const Text('ตรวจผลคำขอเดิม'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('กลับไปหน้าก่อน'),
              ),
            ],
          ),
        ),
      );
}
