import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../navigation/app_tabs.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/tracking_controller.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/face_photo.dart';
import 'login_screen.dart';

/// โครงหลักของแอปหลังล็อกอิน — sidebar + แท็บ
///
/// สิ่งที่ต้องทำงานตลอดไม่ว่าจะเปิดแท็บไหน ถูกยกมาไว้ที่นี่ทั้งหมด:
///   - ติดตามตำแหน่ง (TrackingController) และการทวงสิทธิ์ "อนุญาตตลอดเวลา"
///   - เด้งออกจากระบบตอน 4 ทุ่ม
/// ตัวแท็บจึงเหลือแค่หน้าที่แสดงผลของตัวเอง
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// จอกว้างกว่านี้ = ตรึง sidebar ไว้ข้างจอไปเลย (แท็บเล็ต/แนวนอน)
  static const double _pinnedSidebarBreakpoint = 900;

  final TrackingController _tracking = TrackingController();
  late final List<AppTab> _tabs = buildAppTabs(_tracking);
  int _index = 0;

  Timer? _sessionTimer;
  Timer? _permissionNagTimer;
  bool _permissionDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tracking.addListener(_onTrackingChanged);
    _armSessionTimer();
    _startTracking();
  }

  void _onTrackingChanged() {
    if (mounted) setState(() {}); // sidebar โชว์สถานะการติดตามด้วย
  }

  Future<void> _startTracking() async {
    final access = await _tracking.ensure(prompt: true);
    if (!access.isAlways) await _showPermissionDialog(access);

    // ทวงสิทธิ์ "อนุญาตตลอดเวลา" ซ้ำเรื่อยๆ จนกว่าจะได้ หรือจนออกจากระบบ
    _permissionNagTimer?.cancel();
    _permissionNagTimer = Timer.periodic(
      Config.locationPermissionNagInterval,
      (_) => _nagForAlwaysPermission(),
    );
  }

  Future<void> _nagForAlwaysPermission() async {
    if (!ApiService.isLoggedIn) return;
    if (_tracking.isHealthy) return;
    final access = await _tracking.ensure(prompt: true);
    if (!access.isAlways) await _showPermissionDialog(access);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timer ไม่เดินตอนแอปถูกพักไว้ (หรือเครื่องดับไปทั้งคืน)
    // กลับมาเมื่อไหร่จึงต้องเทียบเวลาใหม่ทุกครั้ง
    if (state != AppLifecycleState.resumed) return;
    _armSessionTimer();
    // ผู้ใช้อาจเพิ่งไปกด "อนุญาตตลอดเวลา" ในหน้าตั้งค่ามา
    _tracking.ensure();
  }

  /// ตั้งเวลาเด้งออกจากระบบตอน 4 ทุ่ม (ดู Config.sessionEndHour)
  void _armSessionTimer() {
    _sessionTimer?.cancel();
    final left = ApiService.timeLeftInSession;
    if (left == null || left <= Duration.zero) {
      // หมดเวลาไปแล้ว — เด้งออกในเฟรมถัดไป (ห้ามสั่ง Navigator กลางการ build)
      _sessionTimer = Timer(Duration.zero, _forceLogout);
      return;
    }
    _sessionTimer = Timer(left, _forceLogout);
  }

  Future<void> _forceLogout() => _leave(notice: Config.sessionExpiredMessage);

  Future<void> _logout() => _leave();

  void _openMyProfile() {
    final profileIndex = _tabs.indexWhere((tab) => tab.id == 'profile');
    if (profileIndex >= 0) setState(() => _index = profileIndex);
  }

  Future<void> _leave({String? notice}) async {
    _sessionTimer?.cancel();
    _permissionNagTimer?.cancel();
    await _tracking.stop();
    await ApiService.logout();
    // รูปใบหน้าถูก cache ไว้ในหน่วยความจำ — เครื่องที่พนักงานใช้ร่วมกัน
    // ต้องไม่เห็นรูปของคนก่อนหน้าหลังสลับบัญชี
    FacePhoto.clearCache();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(notice: notice)),
      (route) => false,
    );
  }

  Future<void> _showPermissionDialog(LocationAccess access) async {
    if (!mounted || _permissionDialogOpen) return;
    _permissionDialogOpen = true;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ต้องอนุญาตตำแหน่งตลอดเวลา'),
        content: Text(
          '${access.message}\n\n'
          'ระบบต้องบันทึกตำแหน่งต่อเนื่องตั้งแต่เข้าสู่ระบบจนกว่าจะออกจากระบบ '
          'ไม่ว่าจะอยู่ที่ทำงานหรืออยู่บ้าน '
          'กรุณาเลือก "อนุญาตตลอดเวลา" ในหน้าตั้งค่าสิทธิ์ตำแหน่ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('later'),
            child: const Text('ไว้ทีหลัง'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              access == LocationAccess.serviceOff ? 'gps' : 'settings',
            ),
            child: Text(
              access == LocationAccess.serviceOff
                  ? 'เปิด GPS'
                  : 'เปิดหน้าตั้งค่า',
            ),
          ),
        ],
      ),
    );
    _permissionDialogOpen = false;

    if (choice == 'settings') await LocationService.openSettings();
    if (choice == 'gps') await LocationService.openLocationSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _permissionNagTimer?.cancel();
    _tracking.removeListener(_onTrackingChanged);
    _tracking.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinned =
        MediaQuery.sizeOf(context).width >= _pinnedSidebarBreakpoint;
    final current = _tabs[_index];
    final account = ApiService.account;

    // IndexedStack = สลับแท็บแล้วสถานะของแท็บเดิมยังอยู่ (ไม่ต้องโหลดใหม่ทุกครั้ง)
    final body = IndexedStack(
      index: _index,
      children: [
        for (final tab in _tabs) Builder(builder: tab.builder),
      ],
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo-checkin.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Text(current.label),
          ],
        ),
        actions: [
          if (account != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'เปิดบัญชีของฉัน',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openMyProfile,
                  child: EmployeeFacePhoto(
                    employeeId: account.id,
                    fallbackText: account.initial,
                    size: 38,
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: pinned
          ? null
          : Builder(
              builder: (context) => AppSidebar(
                tabs: _tabs,
                currentIndex: _index,
                onSelect: (index) {
                  setState(() => _index = index);
                  Navigator.of(context).pop();
                },
                onLogout: () {
                  Navigator.of(context).pop();
                  _logout();
                },
                tracking: _tracking,
              ),
            ),
      body: body,
    );

    if (!pinned) return scaffold;

    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            pinned: true,
            tabs: _tabs,
            currentIndex: _index,
            onSelect: (index) => setState(() => _index = index),
            onLogout: _logout,
            tracking: _tracking,
          ),
          Expanded(child: scaffold),
        ],
      ),
    );
  }
}
