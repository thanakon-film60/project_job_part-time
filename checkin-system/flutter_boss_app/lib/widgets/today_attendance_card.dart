import 'package:flutter/material.dart';

import '../services/attendance_service.dart';
import '../services/work_schedule.dart';

/// การ์ด "การลงเวลาวันนี้" — รายการเข้างาน/ออกงานของวันนี้แบบ List
/// พร้อมสรุปว่าเข้างานกี่โมง และรวมเวลาทำงานไปแล้วเท่าไร
class TodayAttendanceCard extends StatelessWidget {
  final DayAttendance? attendance;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  const TodayAttendanceCard({
    super.key,
    required this.attendance,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final data = attendance;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data == null
                        ? 'การลงเวลาวันนี้'
                        : 'การลงเวลาวันนี้ ${thaiDate(data.day)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'โหลดใหม่',
                    icon: const Icon(Icons.refresh),
                    onPressed: onRefresh,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (error != null)
              _Message(
                icon: Icons.wifi_off,
                color: Colors.redAccent,
                text: error!,
              )
            else if (data == null)
              const _Message(
                icon: Icons.hourglass_empty,
                color: Colors.black45,
                text: 'กำลังโหลดรายการลงเวลา...',
              )
            else ...[
              _Summary(attendance: data),
              const SizedBox(height: 8),
              if (data.isEmpty)
                const _Message(
                  icon: Icons.info_outline,
                  color: Colors.black45,
                  text: 'วันนี้ยังไม่มีการลงเวลา — กดปุ่มเข้างานด้านล่างเพื่อเริ่ม',
                )
              else
                ...data.records.map((record) => _RecordTile(record: record)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final DayAttendance attendance;

  const _Summary({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final firstIn = attendance.firstCheckIn;
    final lastOut = attendance.lastCheckOut;
    final worked = attendance.workedAt();
    final working = attendance.isWorking;
    // อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่มีเวลาทำงานและไม่ต้องรอออกงาน
    final homeOnly = attendance.isHomeOnly;
    final verdict = WorkScheduleService.evaluateDay(attendance);
    final accent =
        homeOnly ? Colors.indigo : (working ? Colors.green : Colors.blueGrey);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                homeOnly
                    ? Icons.home
                    : (working
                        ? Icons.play_circle_fill
                        : Icons.pause_circle_filled),
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  homeOnly
                      ? 'อยู่บ้าน — ไม่ได้ไปทำงาน'
                      : (working
                          ? 'กำลังทำงานอยู่'
                          : 'ยังไม่ได้เริ่มงาน / ออกงานแล้ว'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: homeOnly ? Colors.indigo : accent,
                  ),
                ),
              ),
            ],
          ),
          // สาย / ตรงเวลา ของวันนี้ — ยึดการเข้างานครั้งแรกเป็นตัวตัดสิน
          if (verdict.applies) ...[
            const SizedBox(height: 8),
            _VerdictBadge(verdict: verdict),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'เข้างานครั้งแรก',
                  value:
                      firstIn == null ? '-' : '${thaiClock(firstIn.timestamp)} น.',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'ออกงานล่าสุด',
                  value:
                      lastOut == null ? '-' : '${thaiClock(lastOut.timestamp)} น.',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'รวมเวลาทำงาน',
                  value: (attendance.isEmpty || homeOnly)
                      ? '-'
                      : humanDuration(worked),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ป้าย "สาย / ตรงเวลา" พร้อมบอกเวลาทำงานมาตรฐานกำกับไว้
///
/// สายหรือออกก่อนใช้สีส้มเข้ม ไม่ใช่สีแดง — เป็นข้อมูลให้พนักงานรู้ตัว
/// ไม่ใช่ error ที่ต้องแก้ (ตัวเลขจริงที่ HR ใช้อยู่ที่ฝั่ง backend/LINE)
class _VerdictBadge extends StatelessWidget {
  final AttendanceVerdict verdict;

  const _VerdictBadge({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final attention = verdict.needsAttention;
    final color = attention ? Colors.deepOrange : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            attention ? Icons.warning_amber_rounded : Icons.check_circle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'เวลาทำงาน ${WorkScheduleService.schedule.rangeText}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final CheckInRecord record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final isIn = record.isCheckIn;
    final atHome = record.atHome;
    final color =
        atHome ? Colors.indigo : (isIn ? Colors.green : Colors.deepOrange);
    final place = (record.officeName ?? '').trim();
    final distance = record.distanceKm < 1
        ? '${(record.distanceKm * 1000).toStringAsFixed(0)} ม.'
        : '${record.distanceKm.toStringAsFixed(2)} กม.';
    final verdict = WorkScheduleService.evaluateRecord(record);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          atHome ? Icons.home : (isIn ? Icons.login : Icons.logout),
          color: color,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              '${atHome ? 'อยู่บ้านแล้ว' : (isIn ? 'เข้างาน' : 'ออกงาน')} '
              '${thaiClock(record.timestamp)} น.',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
          if (verdict.needsAttention) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: Colors.deepOrange.shade700,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${place.isEmpty ? 'ไม่ระบุสถานที่' : place} · ห่าง $distance'
        '${record.withinGeofence ? '' : ' (นอกเขต)'}'
        '${verdict.applies ? ' · ${verdict.label}' : ''}',
        style: TextStyle(
          fontSize: 12,
          color: verdict.needsAttention
              ? Colors.deepOrange.shade700
              : Colors.black54,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Message({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
