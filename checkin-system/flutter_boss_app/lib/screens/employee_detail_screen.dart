import 'package:flutter/material.dart';

import '../config.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../widgets/app_forms.dart';
import '../widgets/face_photo.dart';
import 'employee_edit_screen.dart';

/// แฟ้มพนักงาน 1 คน (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/pages/EmployeeHistoryPage.jsx — ข้อมูลส่วนตัว
/// สถิติของเดือน ประวัติลงเวลา Timeline การแก้ไข และรูปยืนยันตัวตน
/// ทั้งหมดมาจาก request เดียว (/reports/employees/{id}/history)
class EmployeeDetailScreen extends StatefulWidget {
  final int employeeId;

  /// ชื่อที่รู้อยู่แล้วจากหน้าก่อน — ใช้ขึ้นหัวข้อระหว่างรอโหลด
  final String? employeeName;

  const EmployeeDetailScreen({
    super.key,
    required this.employeeId,
    this.employeeName,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late DateTime _month;
  EmployeeHistory? _history;
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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await ApiService.fetchEmployeeHistory(
        widget.employeeId,
        _month.year,
        _month.month,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load employee history failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดประวัติพนักงานไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _edit(EmployeeProfile employee) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeEditScreen(employee: employee)),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final employee = history?.employee;

    return Scaffold(
      appBar: AppBar(
        title: Text(employee?.fullName ?? widget.employeeName ?? 'แฟ้มพนักงาน'),
        actions: [
          if (employee != null)
            IconButton(
              tooltip: 'แก้ไขข้อมูล',
              icon: const Icon(Icons.edit),
              onPressed: () => _edit(employee),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _monthPicker(),
            const SizedBox(height: 12),
            if (_error != null)
              NoticeBox.error(text: _error!, onRetry: _load)
            else if (history == null)
              const NoticeBox.loading(text: 'กำลังโหลดแฟ้มพนักงาน...')
            else ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              _profileCard(history),
              _statsRow(history),
              const SizedBox(height: 12),
              _attendanceCard(history),
              _timelineCard(history),
              _facesCard(history),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthPicker() {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'เดือนก่อนหน้า',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftMonth(-1),
        ),
        Expanded(
          child: Text(
            thaiMonthYear(_month.year, _month.month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton.outlined(
          tooltip: 'เดือนถัดไป',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shiftMonth(1),
        ),
      ],
    );
  }

  Widget _profileCard(EmployeeHistory history) {
    final employee = history.employee;
    final faces = history.faceProfiles;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FacePhoto(
                  recordId: faces.isEmpty ? null : faces.first.id,
                  size: 60,
                  fallbackText: employee.fullName.isEmpty
                      ? '?'
                      : employee.fullName.substring(0, 1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Tag(
                            text: employee.employeeCode,
                            color: Colors.blueGrey,
                          ),
                          if (!employee.profileComplete)
                            const Tag(
                              text: 'ข้อมูลยังไม่ครบ',
                              color: Colors.orange,
                              icon: Icons.warning_amber,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        employee.email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            InfoRow(label: 'แผนก', value: employee.department),
            InfoRow(label: 'ตำแหน่ง', value: employee.position),
            InfoRow(
              label: 'วันเริ่มงาน',
              value: employee.startDate == null
                  ? null
                  : thaiLongDate(employee.startDate!),
            ),
            InfoRow(
              label: 'วันเกิด',
              value: employee.birthDate == null
                  ? null
                  : thaiLongDate(employee.birthDate!),
            ),
            InfoRow(label: 'เบอร์โทร', value: employee.phone),
            InfoRow(label: 'เลขบัตร', value: employee.nationalIdMasked),
            InfoRow(label: 'ที่อยู่', value: employee.addressText),
            InfoRow(
              label: 'ลงทะเบียน',
              value: employee.createdAt == null
                  ? null
                  : thaiDateTime(employee.createdAt),
            ),
            InfoRow(
              label: 'แก้ไขล่าสุด',
              value: employee.updatedAt == null
                  ? 'ยังไม่มีการแก้ไข'
                  : thaiDateTime(employee.updatedAt),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _edit(employee),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('แก้ไขข้อมูลพนักงาน'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(EmployeeHistory history) {
    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.event_available,
            label: 'วันที่มาทำงาน',
            value: '${history.workDays}',
            suffix: 'วัน',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            icon: Icons.login,
            label: 'บันทึกเข้างาน',
            value: '${history.workCheckIns}',
            suffix: 'ครั้ง',
            tone: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            icon: Icons.verified_user,
            label: 'รูปยืนยันตัวตน',
            value: '${history.faceProfiles.length}',
            suffix: 'รูป',
            tone: Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _attendanceCard(EmployeeHistory history) {
    final days = history.byDay;

    return SectionCard(
      title: 'ประวัติการลงเวลา',
      icon: Icons.history,
      child: days.isEmpty
          ? const NoticeBox.empty(
              text: 'ไม่พบประวัติในเดือนนี้ ลองเลือกเดือนอื่นเพื่อดูย้อนหลัง',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in days) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Text(
                      thaiLongDate(entry.key),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final record in entry.value)
                    _RecordRow(record: record),
                ],
              ],
            ),
    );
  }

  Widget _timelineCard(EmployeeHistory history) {
    return SectionCard(
      title: 'Timeline แฟ้มพนักงาน',
      icon: Icons.timeline,
      child: history.events.isEmpty
          ? const NoticeBox.empty(text: 'ยังไม่มีเหตุการณ์ในแฟ้มพนักงาน')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final event in history.events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 5, right: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                thaiDateTime(event.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                              ),
                              if (event.detailText != null)
                                Text(
                                  event.detailText!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _facesCard(EmployeeHistory history) {
    final faces = history.faceProfiles;

    return SectionCard(
      title: 'ประวัติยืนยันใบหน้า',
      icon: Icons.face_retouching_natural,
      child: faces.isEmpty
          ? const NoticeBox.empty(text: 'ยังไม่มีรูปยืนยันตัวตน')
          : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.66,
              ),
              itemCount: faces.length,
              itemBuilder: (context, index) {
                final face = faces[index];
                return FaceTile(
                  recordId: face.id,
                  createdAt: face.createdAt,
                  note: face.note ?? face.sourceLabel,
                );
              },
            ),
    );
  }
}

/// การลงเวลา 1 รายการในหน้าแฟ้มพนักงาน
class _RecordRow extends StatelessWidget {
  final CheckInRecord record;

  const _RecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final atHome = record.atHome;
    final isIn = record.isCheckIn;
    final color = atHome
        ? Colors.deepPurple
        : (isIn ? Colors.green : Colors.deepOrange);
    final place = (record.officeName ?? '').trim();
    final distance = record.distanceKm < 1
        ? '${(record.distanceKm * 1000).toStringAsFixed(0)} ม.'
        : '${record.distanceKm.toStringAsFixed(2)} กม.';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        atHome ? Icons.home : (isIn ? Icons.login : Icons.logout),
        color: color,
        size: 18,
      ),
      title: Text(
        '${atHome ? 'อยู่บ้านแล้ว' : (isIn ? 'เข้างาน' : 'ออกงาน')} '
        '${thaiClock(record.timestamp)} น.',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        '${place.isEmpty ? 'ไม่ระบุสถานที่' : place} · ห่าง $distance'
        '${record.withinGeofence ? '' : ' (นอกเขต)'}',
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
    );
  }
}
