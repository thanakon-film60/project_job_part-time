import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/team_calendar.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/month_calendar.dart';
import '../employee_detail_screen.dart';

/// สีของป้ายสถานที่บนปฏิทิน — ตรงกับ locationVariant ฝั่งเว็บ
Color locationColor(String label) {
  if (label == 'อยู่ที่บ้าน') return Colors.deepPurple;
  if (label == 'นอกเขต') return Colors.orange;
  return Colors.green;
}

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
    if (data == null || data.people.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayPeopleSheet(day: day, people: data.people),
    );
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
                  value: '${data?.days.length ?? 0}',
                  suffix: 'วัน',
                  tone: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
    if (data == null || data.people.isEmpty) return null;

    final first = data.people.first;
    final label = first.locations.isEmpty ? null : first.locations.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 2),
        Tag(
          text: '${data.people.length} คน',
          color: Theme.of(context).colorScheme.primary,
        ),
        if (label != null) ...[
          const SizedBox(height: 2),
          Tag(text: label, color: locationColor(label)),
        ],
      ],
    );
  }
}

/// รายชื่อผู้ที่ลงเวลาในวันที่เลือก
class _DayPeopleSheet extends StatelessWidget {
  final DateTime day;
  final List<TeamCalendarPerson> people;

  const _DayPeopleSheet({required this.day, required this.people});

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
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: people.length,
              separatorBuilder: (_, __) => const Divider(height: 20),
              itemBuilder: (context, index) =>
                  _PersonRow(person: people[index]),
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
