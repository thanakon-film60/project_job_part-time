import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/models/directory.dart';
import 'package:thanakon_box_checkin/widgets/face_gallery.dart';
import 'package:thanakon_box_checkin/widgets/face_photo.dart';

FaceRecord face(int id, {int? sortOrder}) => FaceRecord(
      id: id,
      employeeId: 1,
      source: 'mobile',
      note: 'rup-$id',
      createdAt: DateTime.utc(2026, 8, 20 + id),
      sortOrder: sortOrder,
    );

/// วางแกลเลอรีในกรอบกว้างคงที่ ตำแหน่งของแต่ละช่องจะได้คาดเดาได้ในเทสต์
Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, child: child),
        ),
      ),
    );

/// ลากรูปช่องที่ [from] ไปวางที่ช่องที่ [to]
///
/// ต้องกดค้างให้ครบ kLongPressTimeout ก่อน ไม่งั้น LongPressDraggable
/// จะไม่เริ่มลาก (ท่าเดียวกับที่ผู้ใช้ทำจริงบนมือถือ)
Future<void> dragTile(WidgetTester tester, int from, int to) async {
  final tiles = find.byType(FaceTile);
  final gesture = await tester.startGesture(tester.getCenter(tiles.at(from)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(tiles.at(to)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// PNG ขนาด 1x1 คนละสี ใช้แยกให้ออกว่าตอนนี้จอกำลังแสดงรูปของ id ไหน
final Uint8List redPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
final Uint8List bluePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// bytes ของรูปที่กำลังแสดงอยู่จริงบนจอ
Uint8List? shownBytes(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image));
  for (final image in images) {
    final provider = image.image;
    if (provider is MemoryImage) return provider.bytes;
  }
  return null;
}

void main() {
  setUp(FacePhoto.clearCache);

  testWidgets('ลากรูปมาไว้อันแรกแล้วส่งลำดับใหม่ไป backend', (tester) async {
    List<int>? sent;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2), face(3)],
      onReorder: (ids) async {
        sent = ids;
        return true;
      },
      onDelete: (_) async => true,
    )));
    await tester.pump();

    // ลากใบที่สาม (id 3) ขึ้นมาเป็นรูปประจำตัว
    await dragTile(tester, 2, 0);

    expect(sent, [3, 1, 2]);
  });

  testWidgets('บันทึกลำดับไม่สำเร็จ = ย้อนกลับลำดับเดิม', (tester) async {
    // ผู้ใช้ต้องไม่เห็นลำดับที่เซิร์ฟเวอร์ไม่ได้รับไว้ ไม่งั้นจะเข้าใจผิดว่า
    // จัดเรียบร้อยแล้ว พอเปิดใหม่กลับเป็นของเดิมโดยไม่รู้สาเหตุ
    var calls = 0;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2), face(3)],
      onReorder: (_) async {
        calls++;
        return false;
      },
      onDelete: (_) async => true,
    )));
    await tester.pump();

    await dragTile(tester, 2, 0);
    expect(calls, 1);

    // ลากอีกครั้งต้องได้ผลเหมือนเดิม — แปลว่าลำดับในเครื่องถูกย้อนกลับจริง
    List<int>? second;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2), face(3)],
      onReorder: (ids) async {
        second = ids;
        return true;
      },
      onDelete: (_) async => true,
    )));
    await tester.pump();
    await dragTile(tester, 2, 0);

    expect(second, [3, 1, 2]);
  });

  testWidgets('ลากแล้ววางที่เดิม ไม่ยิง API', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2), face(3)],
      onReorder: (_) async {
        calls++;
        return true;
      },
      onDelete: (_) async => true,
    )));
    await tester.pump();

    await dragTile(tester, 1, 1);

    expect(calls, 0);
  });

  testWidgets('ปุ่มลบต้องยืนยันก่อน — กดยกเลิกแล้วไม่ลบ', (tester) async {
    FaceRecord? deleted;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2)],
      onReorder: (_) async => true,
      onDelete: (item) async {
        deleted = item;
        return true;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('ลบรูปนี้?'), findsOneWidget);

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(deleted, isNull);
    expect(find.byType(FaceTile), findsNWidgets(2));
  });

  testWidgets('ยืนยันลบแล้วรูปหายจากแกลเลอรี', (tester) async {
    FaceRecord? deleted;
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2)],
      onReorder: (_) async => true,
      onDelete: (item) async {
        deleted = item;
        return true;
      },
    )));
    await tester.pump();

    // ปุ่มลบใบแรก = รูปที่อยู่อันดับแรก (รูปประจำตัว)
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบรูป'));
    await tester.pumpAndSettle();

    expect(deleted?.id, 1);
    expect(find.byType(FaceTile), findsOneWidget);
  });

  testWidgets('ลบไม่สำเร็จ = รูปยังอยู่ครบ', (tester) async {
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2)],
      onReorder: (_) async => true,
      onDelete: (_) async => false,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบรูป'));
    await tester.pumpAndSettle();

    expect(find.byType(FaceTile), findsNWidgets(2));
  });

  testWidgets('ป้าย "รูปประจำตัว" ติดอยู่กับรูปแรกเสมอ', (tester) async {
    await tester.pumpWidget(host(FaceGallery(
      faces: [face(1), face(2), face(3)],
      onReorder: (_) async => true,
      onDelete: (_) async => true,
    )));
    await tester.pump();

    expect(find.text('รูปประจำตัว'), findsOneWidget);

    await dragTile(tester, 2, 0);

    // ยังมีใบเดียว และย้ายไปอยู่กับรูปที่เพิ่งลากขึ้นมา
    expect(find.text('รูปประจำตัว'), findsOneWidget);
  });

  // -----------------------------------------------------------------
  // บั๊กที่เจอบนเครื่องจริง: หลังลากสลับลำดับ/ลบรูป วันที่ใต้รูปขยับตาม
  // ลำดับใหม่ แต่ตัวรูปค้างอยู่ที่ช่องเดิม กลายเป็นรูปกับวันที่คนละใบ
  //
  // สาเหตุ: กริดเอา element เดิมมาใช้ซ้ำตาม "ตำแหน่ง" ส่วนตัวโหลดรูป
  // โหลดแค่ครั้งเดียวตอน initState จึงไม่รู้ว่า recordId เปลี่ยนไปแล้ว
  // -----------------------------------------------------------------
  group('รูปต้องตรงกับวันที่เสมอ', () {
    testWidgets('เปลี่ยน recordId แล้วรูปเปลี่ยนตาม ไม่ค้างรูปเดิม',
        (tester) async {
      FacePhoto.seedCache(1, redPixel);
      FacePhoto.seedCache(2, bluePixel);

      await tester.pumpWidget(host(FaceTile(
        recordId: 1,
        createdAt: DateTime.utc(2026, 8, 21),
      )));
      await tester.pump();
      expect(shownBytes(tester), redPixel);

      // ตำแหน่งเดิมในต้นไม้ แต่เป็นรูปคนละใบ
      await tester.pumpWidget(host(FaceTile(
        recordId: 2,
        createdAt: DateTime.utc(2026, 8, 22),
      )));
      await tester.pump();
      expect(shownBytes(tester), bluePixel);
    });

    testWidgets('ลากสลับแล้ว รูปกับวันที่ยังไปด้วยกัน', (tester) async {
      FacePhoto.seedCache(1, redPixel);
      FacePhoto.seedCache(2, redPixel);
      FacePhoto.seedCache(3, bluePixel);

      await tester.pumpWidget(host(FaceGallery(
        faces: [face(1), face(2), face(3)],
        onReorder: (_) async => true,
        onDelete: (_) async => true,
      )));
      await tester.pump();

      await dragTile(tester, 2, 0);

      final tiles = tester.widgetList<FaceTile>(find.byType(FaceTile)).toList();
      expect(tiles.map((tile) => tile.recordId), [3, 1, 2]);
      // ใบที่ลากขึ้นมาต้องมาพร้อมทั้งรูปและวันที่ของตัวเอง
      expect(tiles.first.createdAt, face(3).createdAt);
      expect(tiles.first.primary, isTrue);
    });

    testWidgets('ลบรูปแล้ว ใบที่เหลือไม่สลับรูปกัน', (tester) async {
      FacePhoto.seedCache(1, redPixel);
      FacePhoto.seedCache(2, bluePixel);
      FacePhoto.seedCache(3, bluePixel);

      await tester.pumpWidget(host(FaceGallery(
        faces: [face(1), face(2), face(3)],
        onReorder: (_) async => true,
        onDelete: (_) async => true,
      )));
      await tester.pump();

      // ลบใบแรก — ใบที่เหลือเลื่อนขึ้นมาแทนที่
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบรูป'));
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<FaceTile>(find.byType(FaceTile)).toList();
      expect(tiles.map((tile) => tile.recordId), [2, 3]);
      expect(tiles.first.createdAt, face(2).createdAt);
    });
  });
}
