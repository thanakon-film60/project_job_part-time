import 'package:flutter/material.dart';

import '../config.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';

/// แถบสถานะการติดตามตำแหน่ง
///
/// - ได้สิทธิ์ "ตลอดเวลา" และ service เดินอยู่ = เขียว บอกเวลาที่ส่งพิกัดล่าสุด
/// - ยังไม่ได้สิทธิ์ = ส้ม/แดง พร้อมปุ่มขอสิทธิ์ ค้างไว้จนกว่าจะได้หรือออกจากระบบ
class TrackingStatusCard extends StatelessWidget {
  final LocationAccess access;
  final bool serviceRunning;

  /// กำลังขอสิทธิ์/เปิดบริการอยู่ — ยังไม่ต้องฟ้องว่าติดตามไม่ได้
  final bool preparing;
  final DateTime? lastPingAt;
  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenGps;

  const TrackingStatusCard({
    super.key,
    required this.access,
    required this.serviceRunning,
    required this.preparing,
    required this.lastPingAt,
    required this.onGrant,
    required this.onOpenSettings,
    required this.onOpenGps,
  });

  bool get _healthy => access.isAlways && serviceRunning && !_stale;

  /// ระหว่างกำลังตั้งค่าอยู่ ให้ขึ้นข้อความกลางๆ ไม่ต้องมีปุ่มให้กดแข่งกัน
  bool get _busy => preparing && !_healthy;

  bool get _stale {
    final last = lastPingAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > Config.trackingStaleAfter;
  }

  @override
  Widget build(BuildContext context) {
    final color = _healthy
        ? Colors.green
        : _busy
            ? Colors.blueGrey
            : (access.canTrack ? Colors.orange : Colors.redAccent);

    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _healthy
                      ? Icons.my_location
                      : (_busy ? Icons.location_searching : Icons.location_disabled),
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _healthy
                            ? 'กำลังติดตามตำแหน่งตลอดเวลา'
                            : (_busy
                                ? 'กำลังเปิดการติดตามตำแหน่ง...'
                                : 'การติดตามตำแหน่งยังไม่สมบูรณ์'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _detail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!_healthy && !_busy) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (access == LocationAccess.serviceOff)
                    FilledButton.icon(
                      onPressed: onOpenGps,
                      icon: const Icon(Icons.gps_fixed, size: 18),
                      label: const Text('เปิด GPS'),
                    )
                  else if (!access.isAlways) ...[
                    FilledButton.icon(
                      onPressed: onGrant,
                      icon: const Icon(Icons.verified_user, size: 18),
                      label: const Text('อนุญาตตลอดเวลา'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('เปิดหน้าตั้งค่า'),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: onGrant,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('เริ่มติดตามใหม่'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _detail {
    if (_busy) return 'กำลังขอสิทธิ์และเปิดบริการติดตาม กรุณารอสักครู่';
    if (!access.isAlways) return access.message;
    if (!serviceRunning) {
      return 'บริการติดตามยังไม่ทำงาน กดปุ่มด้านล่างเพื่อเริ่มใหม่';
    }
    final last = lastPingAt;
    if (last == null) {
      return 'กำลังรอส่งพิกัดครั้งแรก (ทุก ${Config.pingIntervalSeconds} วินาที)';
    }
    final text = 'ส่งพิกัดล่าสุด ${thaiClock(last)} น.';
    return _stale
        ? '$text — ขาดช่วงอยู่ ตรวจสัญญาณ GPS/อินเทอร์เน็ต'
        : '$text · ส่งต่อเนื่องจนกว่าจะออกจากระบบ';
  }
}
