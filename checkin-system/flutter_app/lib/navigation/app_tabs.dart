import 'package:flutter/material.dart';

import '../screens/tabs/checkin_tab.dart';
import '../screens/tabs/history_tab.dart';
import '../screens/tabs/places_tab.dart';
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
/// ---------------------------------------------------------------------
List<AppTab> buildAppTabs(TrackingController tracking) {
  return [
    AppTab(
      id: 'checkin',
      label: 'เช็คอินเข้างาน',
      subtitle: 'ตำแหน่งปัจจุบัน + ลงเวลาวันนี้',
      icon: Icons.how_to_reg,
      builder: (_) => CheckInTab(tracking: tracking),
    ),
    AppTab(
      id: 'history',
      label: 'ประวัติการลงเวลา',
      subtitle: 'ย้อนหลัง 30 วัน',
      icon: Icons.history,
      builder: (_) => const HistoryTab(),
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
