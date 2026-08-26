import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/directory.dart';
import 'face_photo.dart';

/// แกลเลอรีรูปใบหน้าที่ลากสลับลำดับได้ และลบรูปที่ไม่ต้องการได้
///
/// **ลำดับมีความหมาย**: รูปแรกในลิสต์คือ "รูปประจำตัว" ที่ระบบเอาไปแสดงทุกที่
/// (หัวเมนู, รายชื่อพนักงาน, หน้าแฟ้มพนักงานของหัวหน้า) พนักงานจึงเลือกเองได้
/// ว่าจะให้คนอื่นเห็นรูปไหน ด้วยการลากรูปนั้นมาไว้อันแรก
///
/// เขียน drag & drop เองด้วย LongPressDraggable + DragTarget แทนที่จะเพิ่ม
/// แพ็กเกจ reorderable grid: Flutter มีแต่ ReorderableListView ที่เป็นลิสต์
/// แนวตั้ง ส่วนรูปต้องเรียงเป็นกริด และตรรกะที่ต้องใช้จริงมีแค่ "ย้ายจาก
/// ตำแหน่ง A ไป B" เท่านั้น
class FaceGallery extends StatefulWidget {
  final List<FaceRecord> faces;

  /// บันทึกลำดับใหม่ — คืน false ถ้าบันทึกไม่สำเร็จ (แกลเลอรีจะย้อนกลับให้เอง)
  final Future<bool> Function(List<int> orderedIds) onReorder;

  /// ลบรูป — คืน false ถ้าลบไม่สำเร็จ
  final Future<bool> Function(FaceRecord face) onDelete;

  const FaceGallery({
    super.key,
    required this.faces,
    required this.onReorder,
    required this.onDelete,
  });

  @override
  State<FaceGallery> createState() => _FaceGalleryState();
}

class _FaceGalleryState extends State<FaceGallery> {
  static const int _columns = 3;
  static const double _spacing = 8;
  static const double _aspectRatio = 0.66;

  /// ลำดับที่กำลังแสดงอยู่ — ขยับทันทีที่ปล่อยนิ้ว ไม่ต้องรอเซิร์ฟเวอร์ตอบ
  late List<FaceRecord> _items = [...widget.faces];

  bool _saving = false;
  int? _draggingIndex;

  @override
  void didUpdateWidget(FaceGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // พ่อแม่โหลดข้อมูลใหม่มา (เพิ่มรูป/รีเฟรช) — ยึดของใหม่เป็นหลัก
    if (!listEquals(
      oldWidget.faces.map((face) => face.id).toList(),
      widget.faces.map((face) => face.id).toList(),
    )) {
      _items = [...widget.faces];
    }
  }

  Future<void> _move(int from, int to) async {
    if (from == to || _saving) return;

    // เก็บลำดับเดิมไว้ย้อนกลับ ถ้าเซิร์ฟเวอร์ปฏิเสธ
    final previous = [..._items];
    setState(() {
      final moved = _items.removeAt(from);
      _items.insert(to, moved);
      _saving = true;
    });
    HapticFeedback.selectionClick();

    final ok = await widget.onReorder(
      _items.map((face) => face.id).toList(growable: false),
    );
    if (!mounted) return;
    setState(() {
      if (!ok) _items = previous;
      _saving = false;
    });
  }

  Future<void> _confirmDelete(FaceRecord face) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบรูปนี้?'),
        content: const Text(
          'รูปยืนยันตัวตนใบนี้จะถูกลบถาวร กู้คืนไม่ได้\n\n'
          'ไม่กระทบรูปที่แนบไปกับการลงเวลาแต่ละครั้ง ซึ่งเก็บแยกไว้ต่างหาก',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('ลบรูป'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final ok = await widget.onDelete(face);
    if (!mounted) return;
    setState(() {
      if (ok) _items.removeWhere((item) => item.id == face.id);
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // คำนวณขนาดช่องเอง เพราะ feedback ของ Draggable ลอยอยู่นอกกริด
        // จึงไม่มีข้อจำกัดขนาดของตัวเองให้ยึด ต้องกำหนดเป็นตัวเลขตรง ๆ
        final cellWidth =
            (constraints.maxWidth - _spacing * (_columns - 1)) / _columns;
        final cellHeight = cellWidth / _aspectRatio;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                crossAxisSpacing: _spacing,
                mainAxisSpacing: _spacing,
                childAspectRatio: _aspectRatio,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) => _slot(
                index: index,
                width: cellWidth,
                height: cellHeight,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _saving ? Icons.cloud_upload : Icons.drag_indicator,
                  size: 14,
                  color: Colors.black38,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _saving
                        ? 'กำลังบันทึก...'
                        : 'กดค้างที่รูปแล้วลากเพื่อสลับลำดับ '
                            '· รูปแรกคือรูปประจำตัวที่คนอื่นเห็น',
                    style: const TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// ช่อง 1 ช่องในกริด = ทั้งจุดที่ลากได้ และจุดที่รับการวางของช่องอื่น
  Widget _slot({
    required int index,
    required double width,
    required double height,
  }) {
    final face = _items[index];
    final tile = _tile(face, index, width: width, height: height);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => _move(details.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: LongPressDraggable<int>(
            data: index,
            // ห้ามลากตอนกำลังบันทึกอยู่ ไม่งั้นลำดับในเครื่องกับบนเซิร์ฟเวอร์
            // จะสวนกันเมื่อคำสั่งสองรอบไปถึงคนละลำดับ
            maxSimultaneousDrags: _saving ? 0 : 1,
            onDragStarted: () {
              HapticFeedback.mediumImpact();
              setState(() => _draggingIndex = index);
            },
            onDragEnd: (_) => setState(() => _draggingIndex = null),
            onDraggableCanceled: (_, __) =>
                setState(() => _draggingIndex = null),
            feedback: SizedBox(
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Opacity(
                  opacity: 0.92,
                  child: _tile(face, index, width: width, height: height,
                      dragging: true),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: tile),
            child: tile,
          ),
        );
      },
    );
  }

  Widget _tile(
    FaceRecord face,
    int index, {
    required double width,
    required double height,
    bool dragging = false,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: FaceTile(
            recordId: face.id,
            createdAt: face.createdAt,
            note: face.note ?? face.sourceLabel,
            // รูปแรก = รูปประจำตัว ต้องมองออกทันทีว่าตอนนี้ใช้ใบไหนอยู่
            primary: index == 0,
          ),
        ),
        if (!dragging)
          Positioned(
            right: 2,
            top: 2,
            child: _DeleteButton(
              enabled: !_saving && _draggingIndex == null,
              onPressed: () => _confirmDelete(face),
            ),
          ),
      ],
    );
  }
}

/// ปุ่มลบมุมขวาบนของรูป — เล็กแต่ยังกดโดนง่าย
class _DeleteButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _DeleteButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.close, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}
