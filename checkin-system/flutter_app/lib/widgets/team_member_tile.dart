import 'package:flutter/material.dart';

import '../services/attendance_service.dart';
import '../services/team_status.dart';
import 'app_forms.dart';
import 'duty_warning_card.dart';
import 'face_photo.dart';

/// สีประจำสถานะของวันนี้ — ใช้ทั้งป้ายในรายชื่อและตัวเลขสรุปด้านบน
/// สีเดียวกับที่ใช้บนปฏิทินทีม เพื่อให้หัวหน้าอ่านสองหน้าจอด้วยสายตาชุดเดียวกัน
Color dutyColor(DutyState state) {
  switch (state) {
    case DutyState.working:
      return const Color(0xFF2E7D32);
    case DutyState.home:
      return Colors.deepPurple;
    case DutyState.absent:
      return kDutyWarningRed;
  }
}

IconData dutyIcon(DutyState state) {
  switch (state) {
    case DutyState.working:
      return Icons.how_to_reg;
    case DutyState.home:
      return Icons.home;
    case DutyState.absent:
      return Icons.gpp_maybe;
  }
}

/// แถวรายชื่อพนักงาน 1 คน พร้อมสถานะของวันนี้และตำแหน่งล่าสุด
///
/// ใช้ร่วมกันระหว่างแท็บภาพรวมทีมกับแท็บข้อมูลพนักงาน — คนเดียวกันจะได้หน้าตา
/// และป้ายสถานะเหมือนกันไม่ว่าหัวหน้าจะเปิดมาจากหน้าไหน
class TeamMemberTile extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onTap;

  /// แสดงบรรทัดตำแหน่งล่าสุดจากเส้นติดตาม (/locations/live)
  final bool showLive;

  const TeamMemberTile({
    super.key,
    required this.member,
    required this.onTap,
    this.showLive = true,
  });

  /// บรรทัดล่างสุด: อยู่ที่ไหน + พิกัดเก่าแค่ไหน (สีของจุดคือสถานะการติดตาม)
  String get _liveText {
    final where = member.whereText;
    if (where == null) return 'ยังไม่เคยส่งพิกัดมา';
    return '$where · ${member.ageText}';
  }

  @override
  Widget build(BuildContext context) {
    final duty = member.duty;
    final color = dutyColor(duty);
    final subtitle = [
      member.employeeCode,
      if (member.profile.roleText.isNotEmpty) member.profile.roleText,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmployeeFacePhoto(
                employeeId: member.id,
                size: 48,
                fallbackText: member.initial,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (duty == DutyState.working) ...[
                          Tag(
                            text: member.firstIn == null
                                ? 'ลงเวลาแล้ว'
                                : 'เข้า ${thaiClock(member.firstIn!)} น.',
                            color: color,
                            icon: Icons.login,
                          ),
                          if (member.lastOut != null)
                            Tag(
                              text: 'ออก ${thaiClock(member.lastOut!)} น.',
                              color: Colors.deepOrange,
                              icon: Icons.logout,
                            ),
                        ] else
                          Tag(
                            text: duty.label,
                            color: color,
                            icon: dutyIcon(duty),
                          ),
                        for (final location in member.locations)
                          Tag(
                            text: location,
                            color: locationColor(location),
                            icon: Icons.place,
                          ),
                        if (!member.faceEnrolled)
                          const Tag(
                            text: 'ยังไม่ลงทะเบียนใบหน้า',
                            color: kDutyWarningRed,
                            icon: Icons.face_retouching_off,
                          ),
                        if (!member.profile.profileComplete)
                          const Tag(
                            text: 'ข้อมูลยังไม่ครบ',
                            color: Colors.orange,
                            icon: Icons.warning_amber,
                          ),
                      ],
                    ),
                    if (showLive) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Tooltip(
                            message: member.liveStatus.label,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: liveStatusColor(member.liveStatus),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _liveText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ],
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
