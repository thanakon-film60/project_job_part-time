import 'package:flutter/material.dart';

/// สีแดงของคำเตือน — ใช้ร่วมกับแท็บทีมของหัวหน้า (screens/tabs/team_tab.dart)
const Color kDutyWarningRed = Color(0xFFD32F2F);

/// ข้อความเตือนเมื่อยังไม่ได้ยืนยันตัวตน
///
/// ต้องตรงกับฝั่งเว็บ (frontend/src/lib/attendance.js — UNVERIFIED_*)
/// พนักงานคนเดียวกันอาจเห็นทั้งสองที่ ถ้าข้อความไม่ตรงกันจะสับสนว่าคนละเรื่อง
const String kUnverifiedTitle = 'ยังไม่ได้ยืนยันตัวตน';
const String kUnverifiedDutyWarning = 'ถือว่ายังไม่ได้รับผิดชอบต่อหน้าที่ในวันนี้';
const String kUnverifiedReasonNoFace =
    'ยังไม่ได้ลงทะเบียนใบหน้า — จึงสแกนหน้าเพื่อลงเวลาไม่ได้';
const String kUnverifiedReasonNoCheckIn =
    'วันนี้ยังไม่ได้ลงเวลา — ไม่มีการสแกนใบหน้ายืนยันตัวตน';

/// สรุปว่าพนักงานคนนี้ยืนยันตัวตนของวันนี้แล้วหรือยัง
///
/// การลงเวลาทุกครั้งต้องสแกนใบหน้าผ่านก่อน "วันนี้ยังไม่มีการลงเวลา" จึงเท่ากับ
/// ยังไม่มีการยืนยันตัวตน ส่วนคนที่ยังไม่เคยลงทะเบียนใบหน้าคือสแกนไม่ได้ตั้งแต่
/// แรก — แยกสองเหตุผลออกจากกัน จะได้รู้ว่าต้องไปแก้ตรงไหน
class DutyVerification {
  final bool faceEnrolled;
  final bool checkedInToday;

  const DutyVerification({
    required this.faceEnrolled,
    required this.checkedInToday,
  });

  List<String> get reasons => [
        if (!faceEnrolled) kUnverifiedReasonNoFace,
        if (!checkedInToday) kUnverifiedReasonNoCheckIn,
      ];

  bool get unverified => reasons.isNotEmpty;
}

/// การ์ดเตือนสีแดง — ขึ้นบนสุดของหน้าเช็คอินเมื่อยังไม่ได้ยืนยันตัวตน
class DutyWarningCard extends StatelessWidget {
  final DutyVerification verification;

  /// ปุ่มลัดไปหน้าลงทะเบียนใบหน้า (ซ่อนถ้าลงทะเบียนไว้แล้ว)
  final VoidCallback? onEnrollFace;

  const DutyWarningCard({
    super.key,
    required this.verification,
    this.onEnrollFace,
  });

  @override
  Widget build(BuildContext context) {
    if (!verification.unverified) return const SizedBox.shrink();

    const red = kDutyWarningRed;
    return Card(
      color: red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: red, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gpp_maybe, color: red, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kUnverifiedTitle,
                    style: TextStyle(
                      color: red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...verification.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(color: red)),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(color: red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠  $kUnverifiedDutyWarning',
                style: TextStyle(
                  color: red,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (!verification.faceEnrolled && onEnrollFace != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEnrollFace,
                  icon: const Icon(Icons.face_retouching_natural),
                  label: const Text('ลงทะเบียนใบหน้าตอนนี้'),
                  style: FilledButton.styleFrom(backgroundColor: red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
