import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thanakon_box_checkin/services/face_framing.dart';
import 'package:thanakon_box_checkin/services/face_service.dart';

/// ภาพขนาด 1000x1000 เพื่อให้พิกัด = สัดส่วน × 1000 อ่านง่าย
const _frame = Size(1000, 1000);
const _target = FaceFrameTarget();

/// สร้างผลตรวจใบหน้าโดยระบุตำแหน่ง/ขนาดเป็นสัดส่วนของภาพ
FaceObservation face({
  double cx = 0.5,
  double cy = 0.46,
  double widthRatio = 0.40,
  double? leftEye,
  double? rightEye,
  double? yaw = 0,
  double? roll = 0,
  int count = 1,
}) {
  final w = widthRatio * _frame.width;
  return FaceObservation(
    faceCount: count,
    box: Rect.fromCenter(
      center: Offset(cx * _frame.width, cy * _frame.height),
      width: w,
      height: w * 1.3,
    ),
    frame: _frame,
    leftEyeOpen: leftEye,
    rightEyeOpen: rightEye,
    yaw: yaw,
    roll: roll,
  );
}

/// ป้อนลำดับค่าความเปิดของตาให้ challenge ทีละเฟรม
void feedEyes(FaceChallenge c, List<double> openness) {
  for (final v in openness) {
    c.update(face(leftEye: v, rightEye: v));
  }
}

void main() {
  group('FaceObservation — สัดส่วนจากกรอบใบหน้า', () {
    test('คำนวณจุดกึ่งกลางและความกว้างเป็นสัดส่วนถูกต้อง', () {
      final f = face(cx: 0.5, cy: 0.4, widthRatio: 0.3);
      expect(f.center!.dx, closeTo(0.5, 0.001));
      expect(f.center!.dy, closeTo(0.4, 0.001));
      expect(f.widthRatio!, closeTo(0.3, 0.001));
    });

    test('ไม่มีใบหน้า = ไม่มีสัดส่วนให้คำนวณ', () {
      const none = FaceObservation.none();
      expect(none.hasFace, isFalse);
      expect(none.center, isNull);
      expect(none.widthRatio, isNull);
    });

    test('ตาข้างเดียวอ่านได้ ก็ยังใช้ค่านั้นได้', () {
      expect(face(leftEye: 0.8, rightEye: null).eyeOpenness, 0.8);
      expect(face(leftEye: null, rightEye: 0.2).eyeOpenness, 0.2);
      expect(face(leftEye: 0.8, rightEye: 0.4).eyeOpenness, closeTo(0.6, 0.001));
      expect(face(leftEye: null, rightEye: null).eyeOpenness, isNull);
    });
  });

  group('การจัดกรอบวงรี', () {
    test('อยู่กลางกรอบขนาดพอดี = ผ่าน', () {
      expect(evaluateFraming(face(), target: _target), FaceFraming.ok);
    });

    test('ไม่มีใบหน้า', () {
      expect(evaluateFraming(const FaceObservation.none()), FaceFraming.noFace);
    });

    test('หลายใบหน้าในกรอบ ต้องไม่ผ่าน', () {
      expect(evaluateFraming(face(count: 3)), FaceFraming.manyFaces);
    });

    test('ไกลเกินไป = บอกให้เข้าใกล้', () {
      expect(evaluateFraming(face(widthRatio: 0.15)), FaceFraming.tooFar);
    });

    test('ใกล้เกินไป = บอกให้ถอย', () {
      expect(evaluateFraming(face(widthRatio: 0.85)), FaceFraming.tooClose);
    });

    test('หน้าหลุดออกนอกวงรี = บอกให้จัดกลาง', () {
      expect(evaluateFraming(face(cx: 0.95)), FaceFraming.offCenter);
      expect(evaluateFraming(face(cy: 0.95)), FaceFraming.offCenter);
    });

    test('เอียงหัวมากเกินไป', () {
      expect(evaluateFraming(face(roll: 30)), FaceFraming.tilted);
      expect(evaluateFraming(face(roll: -30)), FaceFraming.tilted);
      // เอียงเล็กน้อยต้องยังผ่าน คนถือมือถือมักเอียงนิดหน่อยอยู่แล้ว
      expect(evaluateFraming(face(roll: 10)), FaceFraming.ok);
    });

    test('ทุกสถานะมีข้อความบอกผู้ใช้', () {
      for (final s in FaceFraming.values) {
        expect(s.hint, isNotEmpty, reason: '$s');
      }
    });

    test('วงรีที่วาดกับที่ตรวจใช้ตัวเลขชุดเดียวกัน', () {
      // ถ้าสองอย่างนี้หลุดจากกัน ผู้ใช้จะเห็นหน้าอยู่ในกรอบแต่ระบบบอกว่าไม่อยู่
      final oval = _target.ovalIn(const Size(400, 800));
      expect(oval.center.dx, closeTo(0.5 * 400, 0.01));
      expect(oval.center.dy, closeTo(0.46 * 800, 0.01));
      expect(oval.width, closeTo(0.33 * 2 * 400, 0.01));
    });
  });

  group('แปลคำสั่งจาก server', () {
    test('ใช้ action_code เป็นหลักเมื่อมี', () {
      expect(parseFaceAction('ข้อความอะไรก็ได้', code: 'blink'),
          FaceActionKind.blink);
      expect(parseFaceAction('ข้อความอะไรก็ได้', code: 'turn_left'),
          FaceActionKind.turnLeft);
      expect(parseFaceAction('ข้อความอะไรก็ได้', code: 'turn_right'),
          FaceActionKind.turnRight);
      expect(parseFaceAction('ข้อความอะไรก็ได้', code: 'look_straight'),
          FaceActionKind.lookStraight);
    });

    test('ไม่มี code ต้องเดาจากข้อความไทยได้ (รองรับ backend รุ่นเดิม)', () {
      expect(parseFaceAction('กะพริบตา 2 ครั้ง'), FaceActionKind.blink);
      expect(parseFaceAction('หันหน้าไปทางซ้ายช้า ๆ'), FaceActionKind.turnLeft);
      expect(parseFaceAction('หันหน้าไปทางขวาช้า ๆ'), FaceActionKind.turnRight);
      expect(parseFaceAction('หันหน้าตรงกล้อง'), FaceActionKind.lookStraight);
    });

    test('สะกด "กระพริบ" ก็ต้องเข้าใจ', () {
      expect(parseFaceAction('กระพริบตา'), FaceActionKind.blink);
    });

    test('อ่านจำนวนครั้งที่ต้องกะพริบ', () {
      expect(blinkTargetOf('กะพริบตา 2 ครั้ง'), 2);
      expect(blinkTargetOf('กะพริบตา 3 ครั้ง'), 3);
      expect(blinkTargetOf('กะพริบตาช้า ๆ'), 1);
      expect(blinkTargetOf('กะพริบตาสองครั้ง'), 2);
      // เลขเยอะผิดปกติต้องไม่ทำให้ผู้ใช้ติดอยู่ตลอดกาล
      expect(blinkTargetOf('กะพริบตา 99 ครั้ง'), 1);
    });
  });

  group('ตรวจการกะพริบตา — ต้องเห็น เปิด→ปิด→เปิด', () {
    test('ตาเปิดค้างไว้เฉย ๆ ไม่ผ่าน (รูปถ่ายลืมตาต้องไม่ผ่าน)', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.9, 0.9, 0.9, 0.9, 0.9, 0.9]);
      expect(c.isSatisfied, isFalse);
      expect(c.blinkCount, 0);
    });

    test('กะพริบครบ 1 ครั้งแล้วผ่าน', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.9, 0.1, 0.9]);
      expect(c.isSatisfied, isTrue);
      expect(c.blinkCount, 1);
    });

    test('สั่งกะพริบ 2 ครั้ง ต้องกะพริบครบ 2 ถึงผ่าน', () {
      final c = FaceChallenge.fromAction('กะพริบตา 2 ครั้ง', code: 'blink');
      feedEyes(c, [0.9, 0.1, 0.9]);
      expect(c.isSatisfied, isFalse, reason: 'ครั้งเดียวยังไม่พอ');
      feedEyes(c, [0.1, 0.9]);
      expect(c.isSatisfied, isTrue);
      expect(c.blinkCount, 2);
    });

    test('ค่าแกว่งกลาง ๆ ไม่นับเป็นกะพริบ', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.9, 0.5, 0.45, 0.5, 0.55, 0.5]);
      expect(c.isSatisfied, isFalse);
    });

    test('เริ่มจากตาปิดอยู่แล้ว ต้องเปิดก่อนถึงเริ่มนับ', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.1, 0.9]);
      expect(c.isSatisfied, isFalse, reason: 'ยังไม่เคยเห็นรอบเปิด-ปิด-เปิดครบ');
      feedEyes(c, [0.1, 0.9]);
      expect(c.isSatisfied, isTrue);
    });

    test('อ่านค่าตาไม่ได้ ต้องไม่ผ่านและไม่ล่ม', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      for (var i = 0; i < 5; i++) {
        c.update(face(leftEye: null, rightEye: null));
      }
      expect(c.isSatisfied, isFalse);
    });

    test('reset แล้วต้องเริ่มนับใหม่หมด', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.9, 0.1, 0.9]);
      expect(c.isSatisfied, isTrue);
      c.reset();
      expect(c.isSatisfied, isFalse);
      expect(c.blinkCount, 0);
    });
  });

  group('ตรวจการหันหน้า', () {
    test('ต้องเห็นหน้าตรงก่อน แล้วค่อยหัน', () {
      final c = FaceChallenge.fromAction('หันซ้าย', code: 'turn_left');
      // หันค้างไว้ตั้งแต่แรก (เช่นเอารูปถ่ายเอียงมาส่อง) ต้องไม่ผ่าน
      c.update(face(yaw: 40));
      expect(c.isSatisfied, isFalse);
    });

    test('หน้าตรงแล้วหันเกินองศาที่กำหนด = ผ่าน', () {
      final c = FaceChallenge.fromAction('หันซ้าย', code: 'turn_left');
      c.update(face(yaw: 0));
      c.update(face(yaw: 30));
      expect(c.isSatisfied, isTrue);
    });

    test('หันนิดเดียวยังไม่ผ่าน', () {
      final c = FaceChallenge.fromAction('หันขวา', code: 'turn_right');
      c.update(face(yaw: 0));
      c.update(face(yaw: 10));
      expect(c.isSatisfied, isFalse);
    });
  });

  group('มองตรง', () {
    test('มองตรงมาที่กล้อง = ผ่าน', () {
      final c = FaceChallenge.fromAction('หันหน้าตรงกล้อง', code: 'look_straight');
      c.update(face(yaw: 3));
      expect(c.isSatisfied, isTrue);
    });

    test('หันไปข้าง ๆ ยังไม่ผ่าน', () {
      final c = FaceChallenge.fromAction('หันหน้าตรงกล้อง', code: 'look_straight');
      c.update(face(yaw: 35));
      expect(c.isSatisfied, isFalse);
    });
  });

  group('ไม่มีคำสั่ง (หน้าลงทะเบียนใบหน้า / เช็คอินงาน)', () {
    test('ผ่านทันทีที่เห็นหน้าตรง ไม่ต้องทำท่าอะไร', () {
      final c = FaceChallenge.none();
      c.update(face());
      expect(c.isSatisfied, isTrue);
    });
  });

  group('คำแนะนำและความคืบหน้า', () {
    test('ทุกท่ามีข้อความบอกผู้ใช้', () {
      for (final code in ['blink', 'turn_left', 'turn_right', 'look_straight']) {
        final c = FaceChallenge.fromAction('x', code: code);
        expect(c.hintFor(face()), isNotEmpty, reason: code);
      }
    });

    test('กะพริบหลายครั้ง บอกความคืบหน้าเป็นตัวเลข', () {
      final c = FaceChallenge.fromAction('กะพริบตา 2 ครั้ง', code: 'blink');
      expect(c.hintFor(face()), contains('0/2'));
      feedEyes(c, [0.9, 0.1, 0.9]);
      expect(c.hintFor(face()), contains('1/2'));
    });

    test('ทำครบแล้วความคืบหน้าเต็ม 1.0', () {
      final c = FaceChallenge.fromAction('กะพริบตา', code: 'blink');
      feedEyes(c, [0.9, 0.1, 0.9]);
      expect(progressOf(c, face()), 1.0);
    });

    test('ความคืบหน้าอยู่ในช่วง 0..1 เสมอ', () {
      for (final code in ['blink', 'turn_left', 'turn_right', 'look_straight']) {
        final c = FaceChallenge.fromAction('x', code: code);
        for (final yaw in [-90.0, -20.0, 0.0, 20.0, 90.0]) {
          final p = progressOf(c, face(yaw: yaw));
          expect(p, inInclusiveRange(0.0, 1.0), reason: '$code yaw=$yaw');
        }
      }
    });
  });
}
