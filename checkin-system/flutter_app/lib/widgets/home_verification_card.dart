import 'package:flutter/material.dart';

import '../models/home_verification.dart';
import '../services/api_service.dart' show endpointUnavailableCode, sessionExpiredCode;

/// การ์ดสถานะ "ยืนยันตัวตนประจำวัน" ตอนอยู่บ้าน
///
/// ข้อกำหนด (DAILY_HOME_FACE_VERIFICATION_2026-09-11.md หัวข้อ 5):
/// การ์ดนี้ **ห้ามมีช่องเวลาเข้างาน/ออกงานแม้เป็นช่องว่างหรือขีด** และห้ามมี
/// ป้ายประเมินเวลา (สาย/ตรงเวลา/ครบเวลางาน) — อยู่บ้านคือไม่ได้ไปทำงาน
/// ถ้าจะโชว์เวลา ต้องเรียกว่า **"เวลายืนยันตัวตน"** เท่านั้น
class HomeVerificationCard extends StatelessWidget {
  /// null = ยังโหลดไม่เสร็จหรือโหลดไม่ได้ ดู [loadFailed]
  final HomeVerificationDay? day;

  /// โหลดสถานะไม่สำเร็จ — ต้องบอกว่า "ยังตรวจสอบผลไม่ได้"
  /// **ห้ามแสดงว่าผู้ใช้ยังไม่รับผิดชอบ** เพราะเราไม่รู้ผลจริง
  final bool loadFailed;

  /// สาเหตุที่โหลดไม่สำเร็จ ใช้แยกข้อความให้ตรงเหตุจริง
  ///
  /// `endpoint_unavailable` = เซิร์ฟเวอร์ยังไม่ได้อัปเดต กดลองใหม่ก็ไม่มีวันสำเร็จ
  /// `session_expired` = ต้องเข้าสู่ระบบใหม่
  /// null = เหตุอื่น (เน็ต/timeout) กดลองใหม่มีโอกาสสำเร็จ
  final String? failureCode;

  final bool busy;
  final VoidCallback onVerify;
  final VoidCallback onRetryLoad;

  const HomeVerificationCard({
    super.key,
    required this.day,
    required this.onVerify,
    required this.onRetryLoad,
    this.loadFailed = false,
    this.failureCode,
    this.busy = false,
  });

  static String _clock(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (loadFailed) return _shell(_unknownBody(context));
    final current = day;
    if (current == null) return _shell(_loadingBody());
    if (current.verified) return _shell(_verifiedBody(current));
    return _shell(_unverifiedBody());
  }

  Widget _shell(Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );

  Widget _loadingBody() => const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('กำลังตรวจสถานะการยืนยันวันนี้...'),
        ],
      );

  Widget _unknownBody(BuildContext context) {
    // แยกสาเหตุให้ตรงจริง — บอกว่า "เชื่อมต่อไม่สำเร็จ" ทั้งที่เน็ตปกติ
    // ทำให้ผู้ใช้ไล่แก้ผิดทาง (สลับ Wi-Fi/เน็ตมือถือวนไปไม่จบ)
    final unavailable = failureCode == endpointUnavailableCode;
    final expired = failureCode == sessionExpiredCode;

    final (icon, color, title, detail) = switch (failureCode) {
      endpointUnavailableCode => (
          Icons.cloud_off,
          Colors.orange,
          'ฟีเจอร์นี้ยังไม่พร้อมใช้งาน',
          'เซิร์ฟเวอร์ยังไม่ได้อัปเดตให้รองรับการยืนยันตัวตนประจำวัน '
              'ไม่ใช่ปัญหาอินเทอร์เน็ตของคุณ — กดลองใหม่ตอนนี้จะยังไม่สำเร็จ '
              'กรุณาแจ้งผู้ดูแลระบบให้อัปเดตเซิร์ฟเวอร์',
        ),
      sessionExpiredCode => (
          Icons.lock_clock,
          Colors.redAccent,
          'เซสชันหมดอายุ',
          'กรุณาเข้าสู่ระบบใหม่เพื่ออ่านสถานะการยืนยันของวันนี้',
        ),
      _ => (
          Icons.help_outline,
          Colors.blueGrey,
          'ยังตรวจสอบผลการยืนยันไม่ได้',
          'เชื่อมต่อเพื่ออ่านสถานะไม่สำเร็จ จึงยังไม่ทราบว่าวันนี้ยืนยันแล้วหรือยัง',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(detail, style: const TextStyle(color: Colors.black54)),
        // เซสชันหมดอายุต้องไป login ไม่ใช่กดลองใหม่ — ปุ่มจึงไม่ขึ้น
        // ส่วนเซิร์ฟเวอร์ยังไม่อัปเดต ให้กดได้แต่บอกตรง ๆ ว่าเป็นการเช็คซ้ำ
        if (!expired) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetryLoad,
            icon: const Icon(Icons.refresh),
            label: Text(unavailable ? 'เช็คอีกครั้งว่าอัปเดตแล้วหรือยัง' : 'ลองอีกครั้ง'),
          ),
        ],
      ],
    );
  }

  Widget _unverifiedBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_late_outlined, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'วันนี้ยังไม่ได้ยืนยันตัวตน',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'หากไม่ได้ไปทำงาน กรุณาสแกนใบหน้าและยืนยันสถานะที่บ้าน '
            'เพื่อรายงานตัวและแสดงความรับผิดชอบต่อหน้าที่',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onVerify,
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('ยืนยันว่าอยู่บ้าน / ไม่ได้ไปทำงาน'),
            ),
          ),
        ],
      );

  Widget _verifiedBody(HomeVerificationDay current) {
    final latest = current.latest!;
    final times = current.verifications
        .map((item) => _clock(item.verifiedAtLocal))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'ยืนยันตัวตนแล้ว — อยู่บ้าน / ไม่ได้ไปทำงาน',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // "เวลายืนยันตัวตน" เท่านั้น — ห้ามเรียกเวลาเข้างาน และห้ามมีคู่ออกงาน
        Text('เวลายืนยันตัวตน ${_clock(latest.verifiedAtLocal)} น.'),
        if (latest.officeName != null)
          Text('สถานที่: ${latest.officeName}',
              style: const TextStyle(color: Colors.black54)),
        if (times.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'ยืนยันวันนี้ ${times.length} ครั้ง (${times.reversed.join(', ')} น.)',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'การยืนยันนี้ไม่นับเป็นการเข้างาน ไม่มีเวลาเข้า–ออก และไม่คิดชั่วโมงทำงาน',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 12),
        // ยืนยันซ้ำได้เสมอ — แต่ต้องขอโจทย์ใหม่และสแกนใหม่ ไม่ใช่ใช้ผลเดิม
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onVerify,
            icon: const Icon(Icons.refresh),
            label: const Text('ยืนยันสถานะอีกครั้ง'),
          ),
        ),
      ],
    );
  }
}
