import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';

/// รูปใบหน้าที่ต้องแนบ token ถึงจะโหลดได้
///
/// /faces/{id}/photo ถูกกันด้วย JWT (เจ้าของหรือหัวหน้าเท่านั้น) จึงใช้
/// Image.network ตรงๆ ไม่ได้ ต้องดึงเป็น bytes เองแล้วค่อยวาดด้วย Image.memory
///
/// เก็บ cache ไว้ในหน่วยความจำระดับ process เพราะรายชื่อพนักงานวาดรูปเดิมซ้ำ
/// ทุกครั้งที่เลื่อนจอ ถ้าไม่ cache จะยิง request ใหม่ทุกรอบจนเปลืองเน็ต
class FacePhoto extends StatefulWidget {
  final int? recordId;
  final double size;

  /// ตัวอักษรที่โชว์แทนเมื่อยังไม่มีรูป (ปกติคือตัวแรกของชื่อ)
  final String fallbackText;

  const FacePhoto({
    super.key,
    required this.recordId,
    this.size = 48,
    this.fallbackText = '?',
  });

  static final Map<int, Uint8List> _cache = {};

  /// id ของรูปล่าสุดของพนักงานแต่ละคน (ผลจาก /faces/employee/{id})
  ///
  /// รายชื่อพนักงานถูกสร้างใหม่ทุกครั้งที่เลื่อนจอหรือค้นหา ถ้าไม่จำไว้
  /// จะยิงถามรายการรูปของทุกคนซ้ำไม่จบ
  static final Map<int, int?> latestFaceByEmployee = {};
  static final Map<int, Future<int?>> _pendingLatestFace = {};
  static final ValueNotifier<int> avatarRevision = ValueNotifier<int>(0);

  static void setLatestFace(int employeeId, int? faceId) {
    latestFaceByEmployee[employeeId] = faceId;
    avatarRevision.value++;
  }

  static Future<int?> resolveLatestFace(int employeeId) {
    if (latestFaceByEmployee.containsKey(employeeId)) {
      return Future<int?>.value(latestFaceByEmployee[employeeId]);
    }
    final pending = _pendingLatestFace[employeeId];
    if (pending != null) return pending;

    final request = ApiService.fetchEmployeeFaces(employeeId)
        .then((faces) => faces.isEmpty ? null : faces.first.id);
    _pendingLatestFace[employeeId] = request;
    request.then(
      (_) => _pendingLatestFace.remove(employeeId),
      onError: (_) => _pendingLatestFace.remove(employeeId),
    );
    return request;
  }

  /// ล้าง cache ตอนออกจากระบบ — เครื่องที่ใช้ร่วมกันจะได้ไม่เห็นรูปของคนก่อน
  static void clearCache() {
    _cache.clear();
    latestFaceByEmployee.clear();
    _pendingLatestFace.clear();
  }

  /// ใส่รูปเข้า cache ตรง ๆ — ใช้ในเทสต์เท่านั้น เพื่อตรวจว่ารูปที่แสดง
  /// เปลี่ยนตาม recordId จริง โดยไม่ต้องยิงเครือข่าย
  @visibleForTesting
  static void seedCache(int recordId, Uint8List bytes) =>
      _cache[recordId] = bytes;

  /// ลืมรูปที่ถูกลบไปแล้ว — ไม่งั้นภาพยังค้างในหน่วยความจำทั้งที่ลบจากเซิร์ฟเวอร์แล้ว
  ///
  /// ล้าง "รูปประจำตัวของพนักงาน" ทิ้งด้วย เพราะใบที่ลบอาจเป็นใบที่ถูกใช้อยู่
  /// รอบหน้าจะได้ไปถามใหม่ว่าตอนนี้ใช้ใบไหนแทน
  static void forget(int recordId) {
    _cache.remove(recordId);
    final before = latestFaceByEmployee.length;
    latestFaceByEmployee.removeWhere((_, faceId) => faceId == recordId);
    if (latestFaceByEmployee.length != before) avatarRevision.value++;
  }

  @override
  State<FacePhoto> createState() => _FacePhotoState();
}

/// Avatar พนักงานที่ค้นหารูปประจำตัวล่าสุดให้อัตโนมัติ
/// ใช้ร่วมกันใน AppBar, Sidebar และ UI List รายชื่อพนักงาน
class EmployeeFacePhoto extends StatefulWidget {
  final int employeeId;
  final String fallbackText;
  final double size;

  const EmployeeFacePhoto({
    super.key,
    required this.employeeId,
    required this.fallbackText,
    this.size = 48,
  });

  @override
  State<EmployeeFacePhoto> createState() => _EmployeeFacePhotoState();
}

class _EmployeeFacePhotoState extends State<EmployeeFacePhoto> {
  int? _faceId;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    FacePhoto.avatarRevision.addListener(_avatarChanged);
    _resolve();
  }

  @override
  void dispose() {
    FacePhoto.avatarRevision.removeListener(_avatarChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(EmployeeFacePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId) {
      setState(() {
        _faceId = null;
        _resolved = false;
      });
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final employeeId = widget.employeeId;
    if (FacePhoto.latestFaceByEmployee.containsKey(employeeId)) {
      if (!mounted) return;
      setState(() {
        _faceId = FacePhoto.latestFaceByEmployee[employeeId];
        _resolved = true;
      });
      return;
    }
    try {
      final latest = await FacePhoto.resolveLatestFace(employeeId);
      if (!mounted || employeeId != widget.employeeId) return;
      FacePhoto.setLatestFace(employeeId, latest);
      setState(() {
        _faceId = latest;
        _resolved = true;
      });
    } catch (err) {
      debugPrint('Load avatar for employee $employeeId failed: $err');
      if (!mounted || employeeId != widget.employeeId) return;
      FacePhoto.setLatestFace(employeeId, null);
      setState(() => _resolved = true);
    }
  }

  void _avatarChanged() {
    if (!mounted) return;
    if (!FacePhoto.latestFaceByEmployee.containsKey(widget.employeeId)) {
      setState(() => _resolved = false);
      _resolve();
      return;
    }
    final latest = FacePhoto.latestFaceByEmployee[widget.employeeId];
    if (_resolved && latest == _faceId) return;
    setState(() {
      _faceId = latest;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return FacePhoto(
      recordId: _faceId,
      size: widget.size,
      fallbackText: widget.fallbackText,
    );
  }
}

class _FacePhotoState extends State<FacePhoto> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FacePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId) _load();
  }

  Future<void> _load() async {
    final id = widget.recordId;
    if (id == null) {
      setState(() {
        _bytes = null;
        _failed = false;
      });
      return;
    }

    final cached = FacePhoto._cache[id];
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _failed = false;
      });
      return;
    }

    setState(() {
      _bytes = null;
      _failed = false;
    });
    try {
      final bytes = await ApiService.fetchFacePhoto(id);
      if (!mounted) return;
      FacePhoto._cache[id] = bytes;
      setState(() => _bytes = bytes);
    } catch (err) {
      debugPrint('Load face photo $id failed: $err');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _bytes;

    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
          : Center(
              child: widget.recordId == null || _failed
                  ? Text(
                      widget.fallbackText,
                      style: TextStyle(
                        fontSize: widget.size * 0.4,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : SizedBox(
                      width: widget.size * 0.35,
                      height: widget.size * 0.35,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
    );
  }
}

/// รูปใบหน้า 1 ใบในแกลเลอรี — กดแล้วเปิดดูเต็มจอ
///
/// ช่องในกริดแคบมาก (3 คอลัมน์บนจอมือถือ) วันที่กับเวลาจึงถูกแยกคนละบรรทัด
/// ตั้งแต่ต้น ไม่ปล่อยให้ข้อความยาวห่อบรรทัดเอง แล้วโดนตัดท้ายจนอ่านไม่ออก
class FaceTile extends StatelessWidget {
  final int recordId;

  /// เวลาที่บันทึกรูป (UTC จาก backend) — จัดรูปแบบเป็นเวลาไทยให้เอง
  final DateTime? createdAt;
  final String? note;

  /// รูปนี้คือรูปประจำตัวที่คนอื่นเห็น (ใบแรกในลำดับ)
  ///
  /// บอกด้วยกรอบสีกับบรรทัดใต้รูป ไม่ใช่ป้ายทับบนรูป เพราะช่องแคบมาก
  /// ป้ายจะไปทับปุ่มลบที่มุมขวาบนจนอ่านไม่ออกทั้งคู่
  final bool primary;

  const FaceTile({
    super.key,
    required this.recordId,
    required this.createdAt,
    this.note,
    this.primary = false,
  });

  String get _dateText =>
      createdAt == null ? '-' : thaiLongDate(Config.toThai(createdAt!));

  String get _timeText =>
      createdAt == null ? '' : '${thaiClock(createdAt!)} น.';

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final noteText = primary ? 'รูปประจำตัว' : (note?.trim() ?? '');

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: primary
            ? BorderSide(color: accent, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openFullScreen(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // รูปกินที่ที่เหลือหลังหักส่วนข้อความ แทนที่จะบังคับเป็นจัตุรัส
            // แล้วเบียดข้อความจนล้นกรอบ
            Expanded(
              child: _FaceImage(
                // ผูก state ของรูปไว้กับ id ของรูป ไม่ใช่ตำแหน่งในกริด
                // สลับลำดับเมื่อไรก็ได้รูปที่ถูกใบเสมอ
                key: ValueKey(recordId),
                recordId: recordId,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    _timeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                      height: 1.2,
                    ),
                  ),
                  if (noteText.isNotEmpty)
                    Row(
                      children: [
                        if (primary) ...[
                          Icon(Icons.star, size: 10, color: accent),
                          const SizedBox(width: 2),
                        ],
                        Expanded(
                          child: Text(
                            noteText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: primary ? accent : Colors.black45,
                              fontWeight:
                                  primary ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(thaiDateTime(createdAt))),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              child: _FaceImage(recordId: recordId, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

/// รูปเต็มใบ (ไม่ครอบวงกลม) ใช้ทั้งในแกลเลอรีและตอนเปิดดูเต็มจอ
class _FaceImage extends StatefulWidget {
  final int recordId;
  final BoxFit fit;

  const _FaceImage({
    super.key,
    required this.recordId,
    this.fit = BoxFit.cover,
  });

  @override
  State<_FaceImage> createState() => _FaceImageState();
}

class _FaceImageState extends State<_FaceImage> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// รูปที่ต้องแสดงเปลี่ยนไปแล้ว ต้องโหลดใหม่
  ///
  /// สำคัญมากตอนลากสลับลำดับหรือลบรูป: กริดเอา element เดิมมาใช้ซ้ำ
  /// ตาม "ตำแหน่ง" ในลิสต์ ถ้าไม่โหลดใหม่ตรงนี้ วันที่ใต้รูปจะขยับตามลำดับใหม่
  /// แต่ตัวรูปค้างอยู่ที่เดิม กลายเป็นรูปกับวันที่ไม่ตรงกัน
  @override
  void didUpdateWidget(_FaceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId) {
      setState(() {
        _bytes = null;
        _error = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final cached = FacePhoto._cache[widget.recordId];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final bytes = await ApiService.fetchFacePhoto(widget.recordId);
      FacePhoto._cache[widget.recordId] = bytes;
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
    }
    if (_error != null) {
      return const ColoredBox(
        color: Color(0x11000000),
        child: Center(
          child: Icon(Icons.broken_image, color: Colors.black26),
        ),
      );
    }
    return const ColoredBox(
      color: Color(0x11000000),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
