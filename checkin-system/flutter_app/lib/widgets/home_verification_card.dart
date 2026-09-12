import 'package:flutter/material.dart';

import '../models/home_verification.dart';

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

  final bool busy;
  final VoidCallback onVerify;
  final VoidCallback onRetryLoad;

  const HomeVerificationCard({
    super.key,
    required this.day,
    required this.onVerify,
    required this.onRetryLoad,
    this.loadFailed = false,
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

  Widget _unknownBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.blueGrey),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ยังตรวจสอบผลการยืนยันไม่ได้',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'เชื่อมต่อเพื่ออ่านสถานะไม่สำเร็จ จึงยังไม่ทราบว่าวันนี้ยืนยันแล้วหรือยัง',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetryLoad,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองอีกครั้ง'),
          ),
        ],
      );

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
