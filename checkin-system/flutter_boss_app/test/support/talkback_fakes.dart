import 'dart:async';

import 'package:thanakon_box_boss/models/camera.dart';
import 'package:thanakon_box_boss/services/camera_talkback_service.dart';

/// ตัวปลอมของ TiRTC ที่ใช้ร่วมกันทั้ง unit test และ widget test
///
/// เทสต์เรียก native TiRTC จริงไม่ได้ (ไม่มี runtime ให้โหลดในเครื่องเทสต์)
/// ตรรกะยกเลิก/เก็บกวาดจึงต้องพิสูจน์ผ่านตัวปลอมนี้แทน
/// สายปลอมที่จดไว้ว่าถูกสั่งอะไรไปบ้าง — ใช้ยืนยันว่า cleanup ครบจริง
class FakeLink implements TalkbackLink {
  FakeLink({this.failStart = false});

  final bool failStart;

  int startCalls = 0;
  int closeCalls = 0;

  @override
  void Function(String message)? onDropped;

  @override
  Future<void> startMic() async {
    startCalls++;
    if (failStart) throw const TalkbackException('เปิดไมค์ไม่สำเร็จ (ทดสอบ)');
  }

  @override
  Future<void> close() async => closeCalls++;

  /// จำลองสายหลุดเองระหว่างพูด
  void drop(String message) => onDropped?.call(message);
}

class FakeEngine implements TalkbackEngine {
  FakeEngine({this.failOpen = false, this.failStart = false});

  bool failOpen;
  final bool failStart;

  int openCalls = 0;
  final List<FakeLink> links = [];

  /// ค้างไว้ตรงขั้น open จนกว่าเทสต์จะสั่งปล่อย — ใช้จำลอง "ปล่อยนิ้วระหว่างต่อ"
  Completer<void>? gate;

  FakeLink get lastLink => links.last;

  @override
  Future<TalkbackLink> open(
    CameraTalkbackSession session, {
    required Duration timeout,
  }) async {
    openCalls++;
    if (gate != null) await gate!.future;
    if (failOpen) throw const TalkbackException('ต่อไปยังกล้องไม่สำเร็จ (ทดสอบ)');
    final link = FakeLink(failStart: failStart);
    links.add(link);
    return link;
  }
}
