import 'package:flutter/material.dart';

import '../screens/tabs/camera_tab.dart';
import '../screens/tabs/checkin_tab.dart';
import '../screens/tabs/employees_tab.dart';
import '../screens/tabs/history_tab.dart';
import '../screens/tabs/live_map_tab.dart';
import '../screens/tabs/overview_tab.dart';
import '../screens/tabs/places_tab.dart';
import '../screens/tabs/profile_tab.dart';
import '../screens/tabs/team_tab.dart';
import '../services/api_service.dart';
import '../services/tracking_controller.dart';

/// เมนู 1 อันบน sidebar = เนื้อหา 1 แท็บ
class AppTab {
  /// ใช้อ้างอิงในโค้ด/บันทึกแท็บล่าสุด — อย่าเปลี่ยนหลังปล่อยเวอร์ชันแล้ว
  final String id;

  /// ชื่อบน sidebar และบนแถบด้านบน
  final String label;

  /// คำอธิบายสั้นใต้ชื่อบน sidebar (ใส่ null ถ้าไม่ต้องการ)
  final String? subtitle;

  final IconData icon;

  /// เนื้อหาของแท็บ — สร้างครั้งเดียวแล้วถูกเก็บสถานะไว้ใน IndexedStack
  final WidgetBuilder builder;

  const AppTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.subtitle,
  });
}

/// ---------------------------------------------------------------------
/// รายการแท็บทั้งหมดของแอป
///
/// **เพิ่มแท็บใหม่ = เพิ่ม AppTab หนึ่งตัวในลิสต์นี้ แล้วสร้างไฟล์หน้าจอใน
/// lib/screens/tabs/ เท่านั้น** ไม่ต้องแก้ AppShell หรือ sidebar เลย
/// ลำดับในลิสต์ = ลำดับบนเมนู
///
/// แท็บของหัวหน้าจะโผล่เฉพาะบัญชีที่ is_manager = true (มาจาก /auth/login)
/// การซ่อนเมนูเป็นแค่เรื่องความสะดวก — ตัวกันจริงคือ require_manager
/// ที่ backend ซึ่งกันไว้ทุก endpoint ของหัวหน้าอยู่แล้ว
/// ---------------------------------------------------------------------
List<AppTab> buildAppTabs(TrackingController tracking) {
  return [
    // หัวหน้าเปิดแอปมาต้องเจอภาพรวมทีมก่อน — AppShell เริ่มที่แท็บแรกเสมอ
    // ส่วนพนักงานทั่วไปยังเจอหน้าเช็คอินเป็นหน้าแรกเหมือนเดิม
    if (ApiService.isManager)
      AppTab(
        id: 'overview',
        label: 'ภาพรวมทีม',
        subtitle: 'วันนี้ใครมา · ใครยังไม่ลงเวลา',
        icon: Icons.dashboard,
        builder: (_) => const OverviewTab(),
      ),
    AppTab(
      id: 'checkin',
      label: 'เช็คอินเข้างาน',
      subtitle: 'ตำแหน่งปัจจุบัน + ลงเวลาวันนี้',
      icon: Icons.how_to_reg,
      builder: (_) => CheckInTab(tracking: tracking),
    ),
    if (ApiService.isManager) ...[
      AppTab(
        id: 'team',
        label: 'ปฏิทินทีม',
        subtitle: 'ใครลงเวลาวันไหนบ้าง',
        icon: Icons.calendar_month,
        builder: (_) => const TeamTab(),
      ),
      AppTab(
        id: 'employees',
        label: 'ข้อมูลพนักงาน',
        subtitle: 'รายชื่อ · สถานะวันนี้ · แฟ้มประวัติ',
        icon: Icons.groups,
        builder: (_) => const EmployeesTab(),
      ),
      AppTab(
        id: 'live-map',
        label: 'แผนที่ติดตาม',
        subtitle: 'ตำแหน่งล่าสุดของทุกคน',
        icon: Icons.map,
        builder: (_) => const LiveMapTab(),
      ),
      AppTab(
        id: 'camera',
        label: 'กล้องวงจรปิด',
        subtitle: 'ดูภาพสด · หมุนกล้อง',
        icon: Icons.videocam,
        builder: (_) => const CameraTab(),
      ),
    ],
    AppTab(
      id: 'history',
      label: 'ประวัติการลงเวลา',
      subtitle: 'ย้อนหลัง 30 วัน',
      icon: Icons.history,
      builder: (_) => const HistoryTab(),
    ),
    AppTab(
      id: 'profile',
      label: 'บัญชีของฉัน',
      subtitle: 'ประวัติใบหน้า · เวอร์ชันแอป',
      icon: Icons.account_circle,
      builder: (_) => const ProfileTab(),
    ),
    AppTab(
      id: 'places',
      label: 'สถานที่ & สถานะระบบ',
      subtitle: 'รัศมีที่เช็คอินได้ · การติดตาม',
      icon: Icons.place,
      builder: (_) => PlacesTab(tracking: tracking),
    ),
  ];
}
