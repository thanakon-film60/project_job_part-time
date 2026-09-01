import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/live_location.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../services/team_status.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/duty_warning_card.dart';
import '../../widgets/team_member_tile.dart';
import '../employee_detail_screen.dart';

/// รีเฟรชอัตโนมัติทุกกี่นาที
///
/// ถี่กว่านี้ไม่คุ้ม — หน้านี้ยิงสามเส้นต่อรอบ และ IndexedStack ของ AppShell
/// ทำให้แท็บนี้ยังมีชีวิตอยู่แม้หัวหน้าเปิดแท็บอื่นค้างไว้
/// ใครอยากได้ข้อมูลนาทีต่อนาที มีแท็บแผนที่ติดตามที่รีเฟรชทุก 20 วินาทีอยู่แล้ว
const Duration _refreshInterval = Duration(minutes: 2);

/// แท็บ "ภาพรวมทีม" (หัวหน้าเท่านั้น) — หน้าแรกของหัวหน้า
///
/// ตอบคำถามแรกของทุกเช้าในหน้าจอเดียว: วันนี้ใครมาแล้ว ใครยังไม่ลงเวลา
/// ใครอยู่บ้าน และตอนนี้แต่ละคนอยู่ที่ไหน จากนั้นกดเข้าไปดูแฟ้มรายคนต่อได้
class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  TeamStatus? _status;
  bool _loading = false;
  String? _error;
  Timer? _timer;

  /// กันรอบรีเฟรชใหม่ซ้อนกับ request ที่ยังไม่จบ
  bool _inFlight = false;

  /// เวลาที่โหลดสำเร็จครั้งล่าสุด — ใช้ตอน backend ไม่ได้ส่ง server_time มา
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// [silent] = ไม่ต้องขึ้นตัวหมุน (รอบรีเฟรชอัตโนมัติ)
  /// [force] = ข้าม cache ของ TeamStatus (ผู้ใช้สั่งโหลดใหม่เอง)
  Future<void> _load({bool silent = false, bool force = false}) async {
    if (_inFlight || !ApiService.isLoggedIn || !mounted) return;
    _inFlight = true;
    if (!silent) setState(() => _loading = true);

    try {
      final status = await TeamStatus.load(force: force);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadedAt = DateTime.now();
        _error = null;
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load team overview failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดภาพรวมทีมไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
      });
    } finally {
      _inFlight = false;
    }
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
    // กลับมาจากแฟ้มพนักงาน อาจมีการแก้ไขข้อมูลไป จึงโหลดใหม่ทั้งก้อน
    await _load(silent: true, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TodayHeader(
            day: status?.day,
            updatedAt: status?.serverTime ?? _loadedAt,
            loading: _loading,
            onRefresh: () => _load(force: true),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.how_to_reg,
                  label: 'มาทำงานวันนี้',
                  value: '${status?.countOf(DutyState.working) ?? 0}',
                  suffix: 'คน',
                  tone: dutyColor(DutyState.working),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.gpp_maybe,
                  label: 'ยังไม่ลงเวลาวันนี้',
                  value: '${status?.countOf(DutyState.absent) ?? 0}',
                  suffix: 'คน',
                  tone: dutyColor(DutyState.absent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.home,
                  label: 'ลงเวลาที่บ้าน',
                  value: '${status?.countOf(DutyState.home) ?? 0}',
                  suffix: 'คน',
                  tone: dutyColor(DutyState.home),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.my_location,
                  label: 'กำลังส่งตำแหน่งอยู่',
                  value: '${status?.onlineCount ?? 0}',
                  suffix: 'คน',
                  tone: liveStatusColor(LiveStatus.online),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            NoticeBox.error(text: _error!, onRetry: () => _load(force: true))
          else if (status == null)
            const NoticeBox.loading(text: 'กำลังโหลดภาพรวมทีม...')
          else if (status.members.isEmpty)
            const NoticeBox.empty(text: 'ยังไม่มีพนักงานในระบบ')
          else ...[
            _AbsentSection(members: status.absent, onOpen: _openDetail),
            _PresentSection(members: status.present, onOpen: _openDetail),
          ],
        ],
      ),
    );
  }
}

/// หัวข้อ "วันนี้" พร้อมเวลาที่ข้อมูลอัปเดตล่าสุดและปุ่มโหลดใหม่
class _TodayHeader extends StatelessWidget {
  final DateTime? day;
  final DateTime? updatedAt;
  final bool loading;
  final VoidCallback onRefresh;

  const _TodayHeader({
    required this.day,
    required this.updatedAt,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final today = day;
    final updated = updatedAt;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              Icons.today,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    today == null ? 'ภาพรวมทีมวันนี้' : thaiLongDate(today),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    updated == null
                        ? 'กำลังโหลดข้อมูล...'
                        : 'ข้อมูลเมื่อ ${thaiClock(updated)} น.',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
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
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'โหลดใหม่',
              ),
          ],
        ),
      ),
    );
  }
}

/// กล่องแดง "วันนี้ใครยังไม่ได้ยืนยันตัวตน" — เรื่องที่หัวหน้าต้องตามต่อ
class _AbsentSection extends StatelessWidget {
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;

  const _AbsentSection({required this.members, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final green = dutyColor(DutyState.working);

    if (members.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: green.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.verified_user, color: green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'วันนี้พนักงานลงเวลากันครบทุกคนแล้ว',
                  style: TextStyle(
                    color: green,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kDutyWarningRed.withValues(alpha: 0.08),
            border: Border.all(color: kDutyWarningRed, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gpp_maybe, color: kDutyWarningRed, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'วันนี้ $kUnverifiedTitle ${members.length} คน',
                      style: const TextStyle(
                        color: kDutyWarningRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
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
        ),
        const SizedBox(height: 10),
        for (final member in members)
          TeamMemberTile(member: member, onTap: () => onOpen(member)),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// รายชื่อคนที่ลงเวลาแล้ววันนี้ (รวมคนที่ลงไว้ที่บ้าน)
class _PresentSection extends StatelessWidget {
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;

  const _PresentSection({required this.members, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
          child: Text(
            'ลงเวลาแล้ววันนี้ ${members.length} คน',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        if (members.isEmpty)
          const NoticeBox.empty(text: 'วันนี้ยังไม่มีใครลงเวลา')
        else
          for (final member in members)
            TeamMemberTile(member: member, onTap: () => onOpen(member)),
      ],
    );
  }
}
