import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/team_calendar.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/duty_warning_card.dart';
import '../../widgets/month_calendar.dart';
import '../employee_detail_screen.dart';

/// แท็บ "ปฏิทินทีม" (หัวหน้าเท่านั้น) — พอร์ตจากหน้าแรกของ Boss บนเว็บ
///
/// ตอบคำถามเดียวกับที่หัวหน้าเปิดเว็บดู: วันไหนมีใครลงเวลาบ้าง เข้า-ออกกี่โมง
/// และวันนั้นอยู่ที่ทำงานหรืออยู่บ้าน
class TeamTab extends StatefulWidget {
  const TeamTab({super.key});

  @override
  State<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<TeamTab> {
  late DateTime _month;
  TeamCalendarMonth? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = Config.thaiNow();
    _month = DateTime(today.year, today.month, 1);
    _load();
  }

  Future<void> _load() async {
    if (!ApiService.isLoggedIn || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.fetchTeamCalendar(_month.year, _month.month);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load team calendar failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดปฏิทินทีมไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
      });
    }
  }

  void _changeMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month, 1);
      _data = null;
    });
    _load();
  }

  String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  void _openDay(DateTime day) {
    final data = _data?.byDate[_dateKey(day)];
    // วันที่มีแต่คนขาดก็ต้องกดเข้าไปดูได้ ไม่ใช่เฉพาะวันที่มีคนลงเวลา
    if (data == null || (data.people.isEmpty && data.missing.isEmpty)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayPeopleSheet(
        day: day,
        people: data.people,
        missing: data.missing,
      ),
    );
  }

  /// คนที่ยังไม่ยืนยันตัวตน "ของวันนี้" — เฉพาะตอนดูเดือนปัจจุบัน
  List<TeamCalendarMissing> get _todayMissing {
    final today = Config.thaiNow();
    if (today.year != _month.year || today.month != _month.month) return const [];
    return _data?.byDate[_dateKey(today)]?.missing ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.groups,
                  label: 'พนักงานที่ลงเวลาเดือนนี้',
                  value: '${data?.activeEmployees ?? 0}',
                  suffix: 'คน',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.event_available,
                  label: 'วันที่มีการลงเวลา',
                  value: '${data?.daysWithCheckins ?? 0}',
                  suffix: 'วัน',
                  tone: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_todayMissing.isNotEmpty) ...[
            _MissingSummaryCard(missing: _todayMissing),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            NoticeBox.error(text: _error!, onRetry: _load)
          else ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: MonthCalendar(
                  month: _month,
                  today: Config.thaiNow(),
                  onMonthChanged: _changeMonth,
                  onSelectDay: _openDay,
                  cellBuilder: (day) => _cell(day),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'กดที่วันเพื่อดูรายชื่อและเวลาเข้า–ออก '
              'วันที่มีแต่การลงเวลาที่บ้านจะขึ้นป้าย "อยู่ที่บ้าน" '
              'ซึ่งไม่นับเป็นการมาทำงาน',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }

  /// เนื้อหาในช่องวัน — จอมือถือแคบมาก โชว์จำนวนคน + ป้ายสถานที่ของคนแรก
  Widget? _cell(DateTime day) {
    final data = _data?.byDate[_dateKey(day)];
    if (data == null || (data.people.isEmpty && data.missing.isEmpty)) return null;

    final first = data.people.isEmpty ? null : data.people.first;
    final label = (first == null || first.locations.isEmpty)
        ? null
        : first.locations.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 2),
        // คนขาดขึ้นก่อน — เป็นเรื่องที่ต้องตามต่อ ต่างจากจำนวนคนที่ลงเวลาปกติ
        if (data.missing.isNotEmpty)
          Tag(
            text: 'ขาด ${data.missing.length}',
            color: kDutyWarningRed,
            dense: true,
          ),
        if (data.people.isNotEmpty) ...[
          if (data.missing.isNotEmpty) const SizedBox(height: 2),
          Tag(
            text: '${data.people.length} คน',
            color: Theme.of(context).colorScheme.primary,
            dense: true,
          ),
        ],
        if (label != null) ...[
          const SizedBox(height: 2),
          Tag(text: label, color: locationColor(label), dense: true),
        ],
      ],
    );
  }
}

/// สรุปสีแดง "วันนี้ใครยังไม่ยืนยันตัวตน" — ขึ้นบนสุดของแท็บทีม
class _MissingSummaryCard extends StatelessWidget {
  final List<TeamCalendarMissing> missing;

  const _MissingSummaryCard({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kDutyWarningRed.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: kDutyWarningRed, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gpp_maybe, color: kDutyWarningRed, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'วันนี้ $kUnverifiedTitle ${missing.length} คน',
                    style: const TextStyle(
                      color: kDutyWarningRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...missing.map(
              (person) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '•  ${person.fullName} (${person.employeeCode})'
                  '${person.faceEnrolled ? '' : ' — ยังไม่ได้ลงทะเบียนใบหน้า'}',
                  style: const TextStyle(color: kDutyWarningRed, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '⚠  $kUnverifiedDutyWarning',
              style: TextStyle(
                color: kDutyWarningRed,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// รายชื่อผู้ที่ลงเวลาในวันที่เลือก พร้อมคนที่ยังไม่ได้ยืนยันตัวตนของวันนั้น
class _DayPeopleSheet extends StatelessWidget {
  final DateTime day;
  final List<TeamCalendarPerson> people;
  final List<TeamCalendarMissing> missing;

  const _DayPeopleSheet({
    required this.day,
    required this.people,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'ผู้ที่ลงเวลา — ${thaiLongDate(day)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // คนที่ขาดขึ้นก่อนรายชื่อคนที่ลงเวลา — เป็นเรื่องที่ต้องตามต่อ
                if (missing.isNotEmpty) ...[
                  _MissingListCard(missing: missing),
                  const SizedBox(height: 16),
                ],
                if (people.isEmpty)
                  const Text(
                    'ไม่มีผู้ลงเวลาในวันนี้',
                    style: TextStyle(color: Colors.black45),
                  )
                else
                  for (var index = 0; index < people.length; index++) ...[
                    if (index > 0) const Divider(height: 20),
                    _PersonRow(person: people[index]),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// กล่องแดงในแผ่นรายวัน — ใครยังไม่ได้ยืนยันตัวตนของวันนั้น
class _MissingListCard extends StatelessWidget {
  final List<TeamCalendarMissing> missing;

  const _MissingListCard({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDutyWarningRed.withValues(alpha: 0.08),
        border: Border.all(color: kDutyWarningRed, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$kUnverifiedTitle ${missing.length} คน',
            style: const TextStyle(
              color: kDutyWarningRed,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          ...missing.map(
            (person) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '•  ${person.fullName} (${person.employeeCode})'
                '${person.faceEnrolled ? '' : ' — ยังไม่ได้ลงทะเบียนใบหน้า'}',
                style: const TextStyle(color: kDutyWarningRed, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '⚠  $kUnverifiedDutyWarning',
            style: TextStyle(
              color: kDutyWarningRed,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final TeamCalendarPerson person;

  const _PersonRow({required this.person});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                person.fullName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Tag(text: person.employeeCode, color: Colors.blueGrey),
          ],
        ),
        const SizedBox(height: 6),
        if (person.homeOnly)
          const Row(
            children: [
              Icon(Icons.home, size: 15, color: Colors.deepPurple),
              SizedBox(width: 6),
              Text(
                'อยู่บ้าน — ไม่ได้ไปทำงาน',
                style: TextStyle(fontSize: 13, color: Colors.deepPurple),
              ),
            ],
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login, size: 15, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'เข้า ${person.firstIn == null ? '-' : thaiClock(person.firstIn!)} น.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.logout, size: 15, color: Colors.deepOrange),
                  const SizedBox(width: 4),
                  Text(
                    'ออก ${person.lastOut == null ? '-' : thaiClock(person.lastOut!)} น.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final location in person.locations)
              Tag(
                text: location,
                color: locationColor(location),
                icon: Icons.place,
              ),
            Tag(
              text: 'ลงเวลา ${person.count} ครั้ง',
              color: Colors.blueGrey,
              icon: Icons.schedule,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              // อ่าน navigator ก่อนปิด sheet — หลัง pop แล้ว context ของ sheet
              // ถูกถอดออกจากต้นไม้ จะเรียก Navigator.of(context) อีกไม่ได้
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => EmployeeDetailScreen(
                    employeeId: person.employeeId,
                    employeeName: person.fullName,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.history, size: 18),
            label: const Text('ดูประวัติพนักงาน'),
          ),
        ),
      ],
    );
  }
}
