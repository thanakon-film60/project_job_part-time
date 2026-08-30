import 'package:flutter/material.dart';

import '../services/attendance_service.dart';

const List<String> _weekdays = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

/// ปฏิทินรายเดือน — พอร์ตจาก frontend/src/components/MonthCalendar.jsx
///
/// เขียน grid เองแทนที่จะใช้ CalendarDatePicker ของ Flutter ด้วยเหตุผลเดียว
/// กับฝั่งเว็บ: ช่องวันต้องยัดรายชื่อพนักงาน + ป้ายสถานที่ ซึ่งตัวเลือกวัน
/// สำเร็จรูปไม่ได้ออกแบบมาให้ทำแบบนั้น
class MonthCalendar extends StatelessWidget {
  /// เดือนที่กำลังดู (ใช้แค่ปีกับเดือน)
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  /// กดที่ช่องวัน — ส่งวันที่ตามเวลาไทยกลับไป
  final void Function(DateTime day)? onSelectDay;

  /// เนื้อหาในช่องวัน คืน null ได้ถ้าวันนั้นไม่มีข้อมูล
  final Widget? Function(DateTime day)? cellBuilder;

  /// วันนี้ตามเวลาไทย — ส่งมาเพื่อไฮไลต์ช่อง
  final DateTime today;

  const MonthCalendar({
    super.key,
    required this.month,
    required this.onMonthChanged,
    required this.today,
    this.onSelectDay,
    this.cellBuilder,
  });

  /// ช่องทั้งหมดของตาราง — null = ช่องว่างเติมหัว/ท้ายให้ครบแถวละ 7
  List<DateTime?> get _cells {
    final first = DateTime(month.year, month.month, 1);
    // DateTime.weekday: จันทร์ = 1 ... อาทิตย์ = 7 แต่หัวตารางเริ่มที่อาทิตย์
    final lead = first.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(month.year, month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  bool _isToday(DateTime day) =>
      day.year == today.year &&
      day.month == today.month &&
      day.day == today.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cells = _cells;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'เดือนก่อนหน้า',
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1, 1)),
            ),
            Expanded(
              child: Text(
                thaiMonthYear(month.year, month.month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'เดือนถัดไป',
              icon: const Icon(Icons.chevron_right),
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month + 1, 1)),
            ),
            TextButton(
              onPressed: () => onMonthChanged(DateTime(today.year, today.month, 1)),
              child: const Text('วันนี้'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final weekday in _weekdays)
              Expanded(
                child: Text(
                  weekday,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.72,
              ),
              itemCount: cells.length,
              itemBuilder: (context, index) {
                final day = cells[index];
                if (day == null) {
                  return ColoredBox(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  );
                }
                return _DayCell(
                  day: day,
                  isToday: _isToday(day),
                  content: cellBuilder?.call(day),
                  onTap: onSelectDay == null ? null : () => onSelectDay!(day),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final Widget? content;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    this.content,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = content != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasData
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isToday)
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Text(
                  '${day.day}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              if (content != null)
                // ช่องวันเตี้ยมาก เนื้อหาที่ล้นต้องถูกตัด ไม่ใช่ทำให้ตารางพัง
                //
                // ClipRect เฉยๆ ตัดภาพให้จริง แต่ Column ข้างในยังถูกบีบด้วย
                // ความสูงของช่องอยู่ดี จึงฟ้อง "RenderFlex overflowed" ทุกช่อง
                // ที่มีสามป้าย OverflowBox ปล่อยให้มันสูงตามธรรมชาติก่อน
                // แล้วค่อยให้ ClipRect ตัดส่วนเกินทิ้ง
                Expanded(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: content!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
