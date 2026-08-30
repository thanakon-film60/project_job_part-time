import 'package:flutter/material.dart';

import '../navigation/app_tabs.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/tracking_controller.dart';
import 'face_photo.dart';

/// เมนูด้านข้าง — ใช้ได้ทั้งแบบ Drawer (จอมือถือ) และแบบตรึงไว้ข้างจอ (จอกว้าง)
///
/// เนื้อหาชุดเดียวกัน จึงเพิ่มแท็บที่ [buildAppTabs] ที่เดียวแล้วขึ้นครบทั้งสองแบบ
class AppSidebar extends StatelessWidget {
  final List<AppTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final TrackingController tracking;

  /// true = ตรึงไว้ข้างจอ (ไม่มีปุ่มปิด, มีเส้นคั่นด้านขวา)
  final bool pinned;

  const AppSidebar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
    required this.onLogout,
    required this.tracking,
    this.pinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(tracking: tracking),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (var i = 0; i < tabs.length; i++)
                _TabTile(
                  tab: tabs[i],
                  selected: i == currentIndex,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text(
            'ออกจากระบบ',
            style: TextStyle(color: Colors.redAccent),
          ),
          subtitle: const Text(
            'หยุดติดตามตำแหน่งทันที',
            style: TextStyle(fontSize: 11),
          ),
          onTap: onLogout,
        ),
        const SizedBox(height: 8),
      ],
    );

    if (!pinned) return Drawer(child: SafeArea(child: content));

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(child: content),
    );
  }
}

class _Header extends StatelessWidget {
  final TrackingController tracking;

  const _Header({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ApiService.account;
    final healthy = tracking.isHealthy;
    final lastPing = tracking.lastPingAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (account == null)
                Image.asset(
                  'assets/images/logo-checkin.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                )
              else
                EmployeeFacePhoto(
                  employeeId: account.id,
                  fallbackText: account.initial,
                  size: 42,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THANAKON-BOX',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (account != null)
                      Text(
                        account.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          if (account != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Chip(
                  text: account.employeeCode,
                  color: theme.colorScheme.primary,
                  icon: Icons.badge,
                ),
                // หัวหน้าเห็นเมนูมากกว่าพนักงานทั่วไป จึงต้องบอกให้ชัดว่า
                // ตอนนี้ล็อกอินด้วยสิทธิ์อะไรอยู่ (เครื่องที่ใช้ร่วมกัน)
                if (account.isManager)
                  const _Chip(
                    text: 'หัวหน้า',
                    color: Colors.deepPurple,
                    icon: Icons.shield,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                healthy ? Icons.my_location : Icons.location_disabled,
                size: 16,
                color: healthy ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  healthy
                      ? 'ติดตามตำแหน่งอยู่'
                          '${lastPing == null ? '' : ' · ${thaiClock(lastPing)} น.'}'
                      : 'การติดตามยังไม่สมบูรณ์',
                  style: TextStyle(
                    fontSize: 12,
                    color: healthy ? Colors.green.shade800 : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabTile extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _TabTile({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: color.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(tab.icon, color: selected ? color : Colors.black54),
        title: Text(
          tab.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? color : null,
          ),
        ),
        subtitle: tab.subtitle == null
            ? null
            : Text(
                tab.subtitle!,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
        onTap: onTap,
      ),
    );
  }
}

/// ป้ายเล็กบนหัว sidebar (รหัสพนักงาน / สิทธิ์)
class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Chip({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
