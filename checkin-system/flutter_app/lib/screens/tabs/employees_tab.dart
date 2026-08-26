import 'package:flutter/material.dart';

import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/face_photo.dart';
import '../employee_detail_screen.dart';
import '../employee_register_screen.dart';

/// แท็บ "ข้อมูลพนักงาน" (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/pages/EmployeesPage.jsx — รายชื่อ ค้นหา
/// และทางเข้าไปยังแฟ้มพนักงานรายคนกับหน้าลงทะเบียนพนักงานใหม่
class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  List<EmployeeProfile>? _employees;
  bool _loading = false;
  String? _error;
  String _query = '';

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
      final employees = await ApiService.fetchEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load employees failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดข้อมูลพนักงานไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
      });
    }
  }

  /// รายชื่อที่แสดง = พนักงานทั่วไป (บัญชีหัวหน้าถูกแยกไปนับในการ์ดสรุป)
  List<EmployeeProfile> get _staff =>
      _employees?.where((employee) => !employee.isManager).toList() ?? const [];

  List<EmployeeProfile> get _visible {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return _staff;
    return _staff
        .where((employee) => [
              employee.fullName,
              employee.employeeCode,
              employee.email,
              employee.department,
              employee.position,
            ].any((value) => (value ?? '').toLowerCase().contains(keyword)))
        .toList(growable: false);
  }

  Future<void> _register() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmployeeRegisterScreen()),
    );
    if (created == true) await _load();
  }

  Future<void> _openDetail(EmployeeProfile employee) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeDetailScreen(
          employeeId: employee.id,
          employeeName: employee.fullName,
        ),
      ),
    );
    // กลับมาจากหน้าแฟ้ม อาจมีการแก้ไขข้อมูลไป จึงโหลดรายชื่อใหม่
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final employees = _employees;
    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _register,
            icon: const Icon(Icons.person_add),
            label: const Text('ลงทะเบียนพนักงาน'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.groups,
                  label: 'พนักงานทั้งหมด',
                  value: '${_staff.length}',
                  suffix: 'คน',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.shield,
                  label: 'บัญชีหัวหน้า',
                  value:
                      '${employees?.where((item) => item.isManager).length ?? 0}',
                  suffix: 'บัญชี',
                  tone: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ค้นหาชื่อ รหัส อีเมล แผนก...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            NoticeBox.error(text: _error!, onRetry: _load)
          else if (employees == null)
            const NoticeBox.loading(text: 'กำลังโหลดรายชื่อพนักงาน...')
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'แสดง ${visible.length} จาก ${_staff.length} คน',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (visible.isEmpty)
              NoticeBox.empty(
                text: _staff.isEmpty
                    ? 'ยังไม่มีพนักงานในระบบ'
                    : 'ไม่พบพนักงานที่ค้นหา',
              )
            else
              for (final employee in visible)
                _EmployeeRow(
                  employee: employee,
                  onTap: () => _openDetail(employee),
                ),
          ],
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  final EmployeeProfile employee;
  final VoidCallback onTap;

  const _EmployeeRow({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _EmployeeAvatar(employee: employee),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${employee.employeeCode} · ${employee.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    if (employee.roleText.isNotEmpty)
                      Text(
                        employee.roleText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    if (!employee.profileComplete) ...[
                      const SizedBox(height: 4),
                      const Tag(
                        text: 'ข้อมูลยังไม่ครบ',
                        color: Colors.orange,
                        icon: Icons.warning_amber,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

/// รูปพนักงานในรายชื่อ — ต้องถามก่อนว่าคนนี้มีรูปไหนบ้าง ถึงจะโหลดรูปได้
///
/// ผลถูกจำไว้ใน FacePhoto.latestFaceByEmployee ซึ่งถูกล้างพร้อมกันตอนออกจากระบบ
class _EmployeeAvatar extends StatefulWidget {
  final EmployeeProfile employee;

  const _EmployeeAvatar({required this.employee});

  @override
  State<_EmployeeAvatar> createState() => _EmployeeAvatarState();
}

class _EmployeeAvatarState extends State<_EmployeeAvatar> {
  int? _faceId;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final employeeId = widget.employee.id;
    if (FacePhoto.latestFaceByEmployee.containsKey(employeeId)) {
      setState(() => _faceId = FacePhoto.latestFaceByEmployee[employeeId]);
      return;
    }
    try {
      final faces = await ApiService.fetchEmployeeFaces(employeeId);
      final latest = faces.isEmpty ? null : faces.first.id;
      FacePhoto.latestFaceByEmployee[employeeId] = latest;
      if (!mounted) return;
      setState(() => _faceId = latest);
    } catch (err) {
      debugPrint('Load faces for employee $employeeId failed: $err');
      FacePhoto.latestFaceByEmployee[employeeId] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FacePhoto(
      recordId: _faceId,
      size: 48,
      fallbackText: widget.employee.fullName.isEmpty
          ? '?'
          : widget.employee.fullName.substring(0, 1),
    );
  }
}
