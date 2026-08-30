import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/team_status.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/team_member_tile.dart';
import '../employee_detail_screen.dart';
import '../employee_register_screen.dart';

/// ตัวกรองรายชื่อ — ตอบคำถามที่หัวหน้าถามบ่อยที่สุดด้วยการกดครั้งเดียว
enum _Filter {
  all('ทั้งหมด'),
  absent('ยังไม่ลงเวลาวันนี้'),
  present('ลงเวลาแล้ววันนี้'),
  incomplete('ข้อมูลยังไม่ครบ');

  final String label;

  const _Filter(this.label);

  bool matches(TeamMember member) {
    switch (this) {
      case _Filter.all:
        return true;
      case _Filter.absent:
        return member.duty == DutyState.absent;
      case _Filter.present:
        return member.checkedIn;
      // "ไม่ครบ" รวมคนที่ยังไม่ได้ลงทะเบียนใบหน้าด้วย — เป็นข้อมูลที่ขาดแล้ว
      // ทำให้พนักงานลงเวลาไม่ได้เลย จึงต้องตามเก็บชุดเดียวกับแฟ้มที่กรอกไม่ครบ
      case _Filter.incomplete:
        return !member.profile.profileComplete || !member.faceEnrolled;
    }
  }
}

/// แท็บ "ข้อมูลพนักงาน" (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/pages/EmployeesPage.jsx — รายชื่อ ค้นหา
/// และทางเข้าไปยังแฟ้มพนักงานรายคนกับหน้าลงทะเบียนพนักงานใหม่
///
/// รายชื่อบอกสถานะของ "วันนี้" ไปด้วย (ลงเวลาแล้ว/ยังไม่ลงเวลา + ตำแหน่งล่าสุด)
/// ใช้ก้อนข้อมูลเดียวกับแท็บภาพรวมทีม ตัวเลขสองหน้าจึงตรงกันเสมอ
class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  TeamStatus? _status;
  bool _loading = false;
  String? _error;
  String _query = '';
  _Filter _filter = _Filter.all;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _listKey = GlobalKey();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [force] = ข้าม cache ของ TeamStatus (ผู้ใช้สั่งโหลดใหม่ หรือเพิ่งแก้ข้อมูลมา)
  Future<void> _load({bool force = false}) async {
    if (!ApiService.isLoggedIn || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await TeamStatus.load(force: force);
      if (!mounted) return;
      setState(() {
        _status = status;
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
  List<TeamMember> get _staff => _status?.members ?? const [];

  List<TeamMember> get _visible {
    final keyword = _query.trim().toLowerCase();
    return _staff.where((member) {
      if (!_filter.matches(member)) return false;
      if (keyword.isEmpty) return true;
      return <String?>[
        member.fullName,
        member.employeeCode,
        member.profile.email,
        member.profile.department,
        member.profile.position,
      ].any((value) => (value ?? '').toLowerCase().contains(keyword));
    }).toList(growable: false);
  }

  Future<void> _register() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmployeeRegisterScreen()),
    );
    if (created == true) await _load(force: true);
  }

  Future<void> _openDetail(TeamMember member) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeDetailScreen(
          employeeId: member.id,
          employeeName: member.fullName,
        ),
      ),
    );
    // กลับมาจากหน้าแฟ้ม อาจมีการแก้ไขข้อมูลไป จึงโหลดรายชื่อใหม่
    await _load(force: true);
  }

  /// เปลี่ยนตัวกรองแล้วเลื่อนจอลงไปที่รายชื่อให้เห็นผลทันที
  void _applyFilter(_Filter filter) {
    _searchController.clear();
    setState(() {
      _filter = filter;
      _query = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _listKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final visible = _visible;

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
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
                  onTap: () => _applyFilter(_Filter.all),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.how_to_reg,
                  label: 'ลงเวลาแล้ววันนี้',
                  value: '${status?.present.length ?? 0}',
                  suffix: 'คน',
                  tone: dutyColor(DutyState.working),
                  onTap: () => _applyFilter(_Filter.present),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.gpp_maybe,
                  label: 'ยังไม่ลงเวลาวันนี้',
                  value: '${status?.countOf(DutyState.absent) ?? 0}',
                  suffix: 'คน',
                  tone: dutyColor(DutyState.absent),
                  onTap: () => _applyFilter(_Filter.absent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.shield,
                  label: 'บัญชีหัวหน้า',
                  value: '${status?.managerCount ?? 0}',
                  suffix: 'บัญชี',
                  tone: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: _listKey,
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ค้นหาชื่อ รหัส อีเมล แผนก...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final filter in _Filter.values)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                  labelStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            NoticeBox.error(text: _error!, onRetry: () => _load(force: true))
          else if (status == null)
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
                    : 'ไม่พบพนักงานตามเงื่อนไขที่เลือก',
              )
            else
              for (final member in visible)
                TeamMemberTile(
                  member: member,
                  onTap: () => _openDetail(member),
                ),
          ],
        ],
      ),
    );
  }
}
