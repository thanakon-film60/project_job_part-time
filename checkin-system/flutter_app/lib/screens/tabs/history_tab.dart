import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';

/// แท็บประวัติการลงเวลาย้อนหลัง — 1 การ์ดต่อ 1 วัน กดเพื่อดูรายการในวันนั้น
class HistoryTab extends StatefulWidget {
  final int days;

  const HistoryTab({super.key, this.days = 30});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<DayAttendance>? _days;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!ApiService.isLoggedIn || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AttendanceService.recentDays(days: widget.days);
      if (!mounted) return;
      setState(() {
        _days = data;
        _loading = false;
      });
    } catch (err) {
      debugPrint('Load attendance history failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดประวัติไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ย้อนหลัง ${widget.days} วัน'
                  '${days == null ? '' : ' · ${days.length} วันที่มีการลงเวลา'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'โหลดใหม่',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            _Notice(
              icon: Icons.wifi_off,
              color: Colors.redAccent,
              text: _error!,
            )
          else if (days == null)
            const _Notice(
              icon: Icons.hourglass_empty,
              color: Colors.black45,
              text: 'กำลังโหลดประวัติการลงเวลา...',
            )
          else if (days.isEmpty)
            const _Notice(
              icon: Icons.info_outline,
              color: Colors.black45,
              text: 'ยังไม่มีประวัติการลงเวลาในช่วงนี้',
            )
          else
            ...days.map((day) => _DayCard(day: day)),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DayAttendance day;

  const _DayCard({required this.day});

  /// วันย้อนหลังที่ลืมกดออกงาน ห้ามนับเวลาถึง "ตอนนี้" ไม่งั้นได้เลขเป็นร้อยชั่วโมง
  bool get _isToday {
    final today = Config.thaiNow();
    return day.day.year == today.year &&
        day.day.month == today.month &&
        day.day.day == today.day;
  }

  /// ไปทำงานแล้วลืมกดออกงาน — วันที่อยู่บ้านล้วนไม่นับ เพราะไม่มีออกงานอยู่แล้ว
  bool get _missingCheckOut => day.isWorking && !_isToday;

  /// วันนั้นมีแต่การบันทึกที่บ้าน = ไม่ได้ไปทำงาน
  bool get _homeOnly => day.isHomeOnly;

  @override
  Widget build(BuildContext context) {
    final worked = _isToday ? day.workedAt() : day.workedClosed;
    final firstIn = day.firstCheckIn;
    final lastOut = day.lastCheckOut;

    final accent = _missingCheckOut
        ? Colors.orange
        : (_homeOnly ? Colors.deepPurple : Colors.indigo);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          child: Icon(
            _missingCheckOut
                ? Icons.error_outline
                : (_homeOnly ? Icons.home : Icons.event_available),
            color: accent,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              thaiDate(day.day),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_isToday) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'วันนี้',
                  style: TextStyle(fontSize: 11, color: Colors.green),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          _homeOnly
              ? 'อยู่บ้าน — ไม่ได้ไปทำงาน (ไม่ต้องมีออกงาน)'
              : 'เข้า ${firstIn == null ? '-' : thaiClock(firstIn.timestamp)} น. · '
                  'ออก ${lastOut == null ? '-' : thaiClock(lastOut.timestamp)} น. · '
                  'รวม ${humanDuration(worked)}'
                  '${_missingCheckOut ? ' (ไม่ได้กดออกงาน)' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: _missingCheckOut
                ? Colors.orange.shade800
                : (_homeOnly ? Colors.deepPurple : Colors.black54),
          ),
        ),
        children: day.records.map((record) {
          final isIn = record.isCheckIn;
          final atHome = record.atHome;
          final color = atHome
              ? Colors.deepPurple
              : (isIn ? Colors.green : Colors.deepOrange);
          final place = (record.officeName ?? '').trim();
          final distance = record.distanceKm < 1
              ? '${(record.distanceKm * 1000).toStringAsFixed(0)} ม.'
              : '${record.distanceKm.toStringAsFixed(2)} กม.';
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              atHome ? Icons.home : (isIn ? Icons.login : Icons.logout),
              color: color,
              size: 18,
            ),
            title: Text(
              '${atHome ? 'อยู่บ้านแล้ว' : (isIn ? 'เข้างาน' : 'ออกงาน')} '
              '${thaiClock(record.timestamp)} น.',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${place.isEmpty ? 'ไม่ระบุสถานที่' : place} · ห่าง $distance'
              '${record.withinGeofence ? '' : ' (นอกเขต)'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
