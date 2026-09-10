import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_boss/models/camera.dart';
import 'package:thanakon_box_boss/services/camera_talkback_service.dart';

import 'support/talkback_fakes.dart';

const CameraTalkbackSession _session = CameraTalkbackSession(
  provider: 'tirtc',
  appId: 'app-123',
  remoteId: 'device-abc',
  token: 'v1.payload.signature',
  streamId: 14,
);

void main() {
  group('CameraStatus — ฟิลด์ talkback ใหม่', () {
    test('เซิร์ฟเวอร์รุ่นเก่าที่ยังไม่ส่งฟิลด์ใหม่มา ต้องไม่พังและต้องไม่โชว์ปุ่ม', () {
      final status = CameraStatus.fromJson({
        'enabled': true,
        'reachable': true,
        'host': '192.168.1.101',
        'message': 'พร้อมใช้งาน',
        'audio_supported': true,
        'talkback_supported': true,
        'talkback_note': 'กล้องรองรับ RTSP backchannel',
      });

      expect(status.talkbackSupported, isTrue);
      expect(status.talkbackReady, isFalse);
      expect(status.canTalkback, isFalse,
          reason: 'กล้องรองรับอย่างเดียวไม่พอ ระบบเราต้องมี transport ด้วย');
    });

    test('พร้อมครบและเป็น tirtc จึงจะกดพูดได้', () {
      final status = CameraStatus.fromJson({
        'enabled': true,
        'reachable': true,
        'host': 'h',
        'message': 'ok',
        'talkback_supported': true,
        'talkback_ready': true,
        'talkback_transport': 'tirtc',
        'talkback_token_path': '/camera/talkback/token',
        'talkback_stream_id': 14,
      });

      expect(status.canTalkback, isTrue);
      expect(status.talkbackStreamId, 14);
      expect(status.talkbackTokenPath, '/camera/talkback/token');
    });

    test('transport ที่แอปรุ่นนี้ไม่รู้จัก ต้องไม่โชว์ปุ่ม', () {
      final status = CameraStatus.fromJson({
        'enabled': true,
        'reachable': true,
        'host': 'h',
        'message': 'ok',
        'talkback_ready': true,
        'talkback_transport': 'webrtc-v2',
        'talkback_stream_id': 14,
      });

      expect(status.canTalkback, isFalse);
    });

    test('stream id นอกช่วง 0..15 ต้องไม่โชว์ปุ่ม', () {
      CameraStatus withStream(Object? id) => CameraStatus.fromJson({
            'enabled': true,
            'reachable': true,
            'host': 'h',
            'message': 'ok',
            'talkback_ready': true,
            'talkback_transport': 'tirtc',
            'talkback_stream_id': id,
          });

      expect(withStream(99).canTalkback, isFalse);
      expect(withStream(-1).canTalkback, isFalse);
      expect(withStream(null).canTalkback, isFalse);
      expect(withStream(0).canTalkback, isTrue);
      expect(withStream(15).canTalkback, isTrue);
    });
  });

  group('CameraTalkbackSession', () {
    test('อ่าน response ของ token endpoint ได้ครบ', () {
      final session = CameraTalkbackSession.fromJson({
        'provider': 'tirtc',
        'app_id': 'app-123',
        'remote_id': 'device-abc',
        'token': 'v1.payload.signature',
        'issued_at': 1788355200,
        'expires_at': 1788355320,
        'stream_id': 14,
        'audio_codec': 'g711a',
        'sample_rate_hz': 16000,
        'channels': 1,
      });

      expect(session.appId, 'app-123');
      expect(session.remoteId, 'device-abc');
      expect(session.streamId, 14);
      expect(session.sampleRateHz, 16000);
      expect(session.isUsable, isTrue);
    });

    test('toString ต้องไม่มี token ติดไปด้วย', () {
      expect(_session.toString(), isNot(contains('signature')));
      expect(_session.toString(), contains('tirtc'));
    });

    test('เซิร์ฟเวอร์ตั้งค่าไม่ครบแล้วส่งช่องว่างมา ต้องรู้ว่าใช้ไม่ได้', () {
      final session = CameraTalkbackSession.fromJson({
        'provider': 'tirtc',
        'app_id': '',
        'remote_id': 'device-abc',
        'token': '',
      });
      expect(session.isUsable, isFalse);
    });
  });

  group('CameraTalkbackService', () {
    late FakeEngine engine;
    late int tokenCalls;

    CameraTalkbackService build({
      bool granted = true,
      Future<CameraTalkbackSession> Function()? fetchSession,
    }) {
      tokenCalls = 0;
      return CameraTalkbackService(
        fetchSession: fetchSession ??
            () async {
              tokenCalls++;
              return _session;
            },
        requestPermission: () async => granted,
        engine: engine,
      );
    }

    setUp(() => engine = FakeEngine());

    test('กดพูดแล้วต่อสำเร็จ ไมค์ต้องเริ่มและสถานะเป็น talking', () async {
      final service = build();
      await service.start();

      expect(service.phase, TalkbackPhase.talking);
      expect(service.error, isNull);
      expect(engine.lastLink.startCalls, 1);
    });

    test('ปฏิเสธสิทธิ์ไมค์แล้วต้องไม่ขอ token และไม่แตะ SDK', () async {
      final service = build(granted: false);
      await service.start();

      expect(tokenCalls, 0, reason: 'ยังไม่ได้สิทธิ์ ห้ามขอ token');
      expect(engine.openCalls, 0, reason: 'ยังไม่ได้สิทธิ์ ห้ามเปิดสาย SDK');
      expect(service.phase, TalkbackPhase.idle);
      expect(service.permissionBlocked, isTrue);
      expect(service.error, isNotNull);
    });

    test('ปล่อยนิ้วระหว่างกำลังต่อ ไมค์ต้องไม่เริ่ม และสายที่เปิดไว้ต้องถูกปิด',
        () async {
      final service = build();
      engine.gate = Completer<void>();

      final starting = service.start();
      await Future<void>.delayed(Duration.zero);

      // ผู้ใช้ปล่อยนิ้วตอนที่ open ยังค้างอยู่
      await service.stop();
      engine.gate!.complete();
      await starting;

      expect(engine.lastLink.startCalls, 0,
          reason: 'ปล่อยนิ้วไปแล้ว ห้ามเปิดไมค์ตามหลัง');
      expect(engine.lastLink.closeCalls, greaterThanOrEqualTo(1),
          reason: 'สายที่เปิดไปแล้วต้องถูกปิด ไม่ใช่ค้างกินสายของกล้อง');
      expect(service.phase, TalkbackPhase.idle);
    });

    test('ปล่อยนิ้วหลังเริ่มพูดแล้ว ต้อง cleanup ครบ', () async {
      final service = build();
      await service.start();
      expect(service.phase, TalkbackPhase.talking);

      await service.stop();

      expect(service.phase, TalkbackPhase.idle);
      expect(engine.lastLink.closeCalls, 1);
    });

    test('SDK ต่อไม่ติด ต้องกลับไป idle พร้อมข้อความ แล้วกดใหม่ได้', () async {
      engine.failOpen = true;
      final service = build();
      await service.start();

      expect(service.phase, TalkbackPhase.idle);
      expect(service.error, contains('ต่อไปยังกล้องไม่สำเร็จ'));

      // กดใหม่แล้วต้องไปต่อได้ ไม่ค้างสถานะเดิม
      engine.failOpen = false;
      await service.start();
      expect(service.phase, TalkbackPhase.talking);
      expect(service.error, isNull);
    });

    test('เปิดไมค์ไม่สำเร็จ ต้องปิดสายทิ้งไม่ให้ค้าง', () async {
      engine = FakeEngine(failStart: true);
      final service = build();
      await service.start();

      expect(service.phase, TalkbackPhase.idle);
      expect(service.error, contains('เปิดไมค์ไม่สำเร็จ'));
      expect(engine.lastLink.closeCalls, greaterThanOrEqualTo(1));
    });

    test('ขอ token ไม่ผ่าน (เช่นไม่ใช่หัวหน้า) ต้องโชว์ข้อความจากเซิร์ฟเวอร์',
        () async {
      final service = build(
        fetchSession: () async => throw Exception('ต้องเป็นหัวหน้าเท่านั้น'),
      );
      await service.start();

      expect(service.phase, TalkbackPhase.idle);
      expect(service.error, contains('ต้องเป็นหัวหน้าเท่านั้น'));
      expect(engine.openCalls, 0);
    });

    test('เซิร์ฟเวอร์ส่ง session ที่ใช้ไม่ได้มา ต้องไม่เปิดสาย', () async {
      final service = build(
        fetchSession: () async => const CameraTalkbackSession(
          provider: 'tirtc',
          appId: '',
          remoteId: '',
          token: '',
          streamId: 14,
        ),
      );
      await service.start();

      expect(engine.openCalls, 0);
      expect(service.error, contains('ยังตั้งค่าการพูดออกกล้องไม่ครบ'));
    });

    test('สายหลุดเองระหว่างพูด ต้องหยุดและบอกผู้ใช้', () async {
      final service = build();
      await service.start();

      engine.lastLink.drop('สายพูดหลุด (เน็ตหาย) — กดพูดใหม่ได้');
      await Future<void>.delayed(Duration.zero);

      expect(service.phase, TalkbackPhase.idle);
      expect(service.error, contains('สายพูดหลุด'));
    });

    test('กดพูดซ้อนกันหลายรอบ ต้องไม่เหลือสายค้าง', () async {
      final service = build();
      await service.start();
      await service.start();
      await service.start();

      expect(engine.links.length, 3);
      // รอบก่อน ๆ ต้องถูกปิดหมด เหลือเฉพาะรอบล่าสุดที่ยังเปิดอยู่
      expect(engine.links[0].closeCalls, 1);
      expect(engine.links[1].closeCalls, 1);
      expect(engine.links[2].closeCalls, 0);
      expect(service.phase, TalkbackPhase.talking);
    });

    test('stop และ dispose เรียกซ้ำได้โดยไม่ throw', () async {
      final service = build();
      await service.start();

      await service.stop();
      await service.stop();
      await service.dispose();
      await service.dispose();

      expect(service.phase, TalkbackPhase.idle);
      expect(engine.lastLink.closeCalls, 1);
    });

    test('dispose ไปแล้วกดพูดอีกต้องไม่ทำอะไร', () async {
      final service = build();
      await service.dispose();
      await service.start();

      expect(engine.openCalls, 0);
      expect(service.phase, TalkbackPhase.idle);
    });
  });
}
