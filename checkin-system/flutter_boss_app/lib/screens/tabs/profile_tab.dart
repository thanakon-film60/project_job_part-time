import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/directory.dart';
import '../../services/api_service.dart';
import '../../widgets/app_forms.dart';
import '../../widgets/face_gallery.dart';
import '../../widgets/face_photo.dart';

/// แท็บ "บัญชีของฉัน" — ข้อมูลผู้ใช้ ประวัติใบหน้า และเวอร์ชันแอป
///
/// ฝั่งเว็บกระจายอยู่สองหน้า (การ์ดต้อนรับใน DashboardPage + FaceRecordsPage)
/// บนมือถือรวมเป็นแท็บเดียว เพราะทั้งสองอย่างตอบคำถามเดียวกันคือ
/// "ระบบรู้จักฉันว่าเป็นใคร และเก็บรูปฉันไว้กี่รูป"
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<FaceRecord>? _faces;
  bool _loading = false;
  String? _error;

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
      final faces = await ApiService.fetchMyFaces();
      if (!mounted) return;
      final account = ApiService.account;
      if (account != null) {
        FacePhoto.setLatestFace(
          account.id,
          faces.isEmpty ? null : faces.first.id,
        );
      }
      setState(() {
        _faces = faces;
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load my faces failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดประวัติใบหน้าไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
      });
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// บันทึกลำดับใหม่ที่ผู้ใช้ลากสลับ — คืน false ให้แกลเลอรีย้อนกลับเองถ้าไม่สำเร็จ
  Future<bool> _reorder(List<int> orderedIds) async {
    try {
      final updated = await ApiService.reorderFaces(orderedIds);
      final account = ApiService.account;
      if (account != null) {
        FacePhoto.setLatestFace(
          account.id,
          updated.isEmpty ? null : updated.first.id,
        );
      }
      if (mounted) setState(() => _faces = updated);
      return true;
    } on ApiException catch (err) {
      _notify(err.message);
      return false;
    } catch (err) {
      debugPrint('Reorder faces failed: $err');
      _notify('บันทึกลำดับรูปไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่');
      return false;
    }
  }

  Future<bool> _delete(FaceRecord face) async {
    try {
      await ApiService.deleteFace(face.id);
      // เอาออกจาก cache ด้วย ไม่งั้นรูปที่ลบแล้วยังโผล่จากหน่วยความจำ
      FacePhoto.forget(face.id);
      if (mounted) {
        setState(() {
          _faces = [
            for (final item in _faces ?? const <FaceRecord>[])
              if (item.id != face.id) item,
          ];
        });
      }
      _notify('ลบรูปแล้ว');
      return true;
    } on ApiException catch (err) {
      _notify(err.message);
      return false;
    } catch (err) {
      debugPrint('Delete face failed: $err');
      _notify('ลบรูปไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ApiService.account;
    final faces = _faces;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  FacePhoto(
                    // รูปล่าสุดคือรูปแรก (backend เรียงใหม่สุดขึ้นก่อน)
                    recordId: faces == null || faces.isEmpty ? null : faces.first.id,
                    size: 64,
                    fallbackText: account?.initial ?? '?',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account?.fullName ?? 'ยังไม่ทราบชื่อ',
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
                              text: 'รหัส ${account?.employeeCode ?? '-'}',
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            if (account?.isManager == true)
                              const Tag(
                                text: 'หัวหน้า',
                                color: Colors.deepPurple,
                                icon: Icons.shield,
                              ),
                          ],
                        ),
                        if ((account?.email ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            account!.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SectionCard(
            title: 'ประวัติใบหน้าของฉัน',
            icon: Icons.verified_user,
            trailing: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'โหลดใหม่',
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'รูปเหล่านี้เป็นภาพอ้างอิงเพื่อยืนยันตัวตน '
                  'คุณกับหัวหน้าเท่านั้นที่เปิดดูได้',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  NoticeBox.error(text: _error!, onRetry: _load)
                else if (faces == null)
                  const NoticeBox.loading(text: 'กำลังโหลดประวัติใบหน้า...')
                else if (faces.isEmpty)
                  const NoticeBox.empty(
                    text: 'บัญชีนี้ไม่มีรูปยืนยันตัวตน — '
                        'หัวหน้าลงเวลาได้โดยไม่ต้องสแกนใบหน้า',
                  )
                else
                  FaceGallery(
                    faces: faces,
                    onReorder: _reorder,
                    onDelete: _delete,
                  ),
              ],
            ),
          ),
          const _AppVersionCard(),
        ],
      ),
    );
  }
}

/// เวอร์ชันที่ติดตั้งอยู่ เทียบกับไฟล์ล่าสุดบนเซิร์ฟเวอร์
/// เวอร์ชันของแอปหัวหน้า
///
/// ไม่เทียบกับ /app/info เหมือนแอปพนักงาน เพราะ endpoint นั้นอธิบาย APK
/// ของ "แอปพนักงาน" ตัวเดียว ถ้าเอามาเทียบ หัวหน้าจะเห็นว่ามีเวอร์ชันใหม่
/// แล้วกดโหลดได้แอปผิดตัวมาทับ — แอปหัวหน้าแจกไฟล์กันเองนอกระบบ
class _AppVersionCard extends StatelessWidget {
  const _AppVersionCard();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: 'เวอร์ชันแอป',
      icon: Icons.system_update,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: 'ติดตั้งอยู่', value: Config.appVersion),
          SizedBox(height: 6),
          Text(
            'แอปหัวหน้าแจกไฟล์ APK กันเอง ไม่ได้อัปเดตผ่านหน้าดาวน์โหลด'
            'ของแอปพนักงาน',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
