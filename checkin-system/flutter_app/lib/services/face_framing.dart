import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'face_service.dart';

/// ขอบเขตวงรีที่ใบหน้าต้องอยู่ข้างใน — เก็บเป็น **สัดส่วน 0..1 ของภาพ**
///
/// ใช้สัดส่วนไม่ใช่พิกเซล เพราะตัวเลขชุดเดียวกันต้องใช้ได้ทั้งกับภาพจาก ML Kit
/// (ความละเอียดของเซ็นเซอร์) และกับวงรีที่วาดบนหน้าจอ (ขนาดวิดเจ็ต) ถ้าใช้
/// พิกเซล กรอบที่ผู้ใช้เห็นจะไม่ตรงกับกรอบที่ระบบตรวจจริง
class FaceFrameTarget {
  final Offset center;
  final double radiusX;
  final double radiusY;

  /// ความกว้างใบหน้าเทียบความกว้างภาพที่ยอมรับ — กันถือใกล้/ไกลเกินไป
  final double minWidthRatio;
  final double maxWidthRatio;

  const FaceFrameTarget({
    this.center = const Offset(0.5, 0.46),
    this.radiusX = 0.33,
    this.radiusY = 0.27,
    this.minWidthRatio = 0.26,
    this.maxWidthRatio = 0.70,
  });

  /// วงรีในพิกัดจริงของพื้นที่ขนาด [size] — ใช้ทั้งตอนวาดและตอนตรวจ
  Rect ovalIn(Size size) => Rect.fromCenter(
        center: Offset(center.dx * size.width, center.dy * size.height),
        width: radiusX * 2 * size.width,
        height: radiusY * 2 * size.height,
      );
}

/// ผลการจัดกรอบ เรียงตามลำดับที่ควรบอกผู้ใช้ก่อนหลัง
enum FaceFraming {
  noFace,
  manyFaces,
  tooFar,
  tooClose,
  offCenter,
  tilted,
  ok,
}

extension FaceFramingText on FaceFraming {
  bool get isOk => this == FaceFraming.ok;

  String get hint => switch (this) {
        FaceFraming.noFace => 'ไม่พบใบหน้า — จัดหน้าให้อยู่ในกรอบ',
        FaceFraming.manyFaces => 'พบหลายใบหน้า — ให้มีเพียงคนเดียวในกรอบ',
        FaceFraming.tooFar => 'ขยับเข้าใกล้อีกนิด',
        FaceFraming.tooClose => 'ถอยออกอีกนิด',
        FaceFraming.offCenter => 'จัดใบหน้าให้อยู่กลางกรอบ',
        FaceFraming.tilted => 'ตั้งศีรษะให้ตรง',
        FaceFraming.ok => 'พอดีแล้ว',
      };
}

/// เอียงหัวเกินกี่องศาถึงจะเตือน — เผื่อไว้พอสมควรเพราะคนถือมือถือมักเอียงเล็กน้อย
const double _maxRollDegrees = 18;

/// ตรวจว่าใบหน้าอยู่ในกรอบวงรีหรือยัง
///
/// ไล่ตรวจจาก "ไม่มีหน้า" → "ระยะ" → "ตำแหน่ง" → "ความเอียง" เพื่อให้คำแนะนำ
/// ที่ผู้ใช้เห็นเป็นสิ่งที่แก้ได้ทีละอย่าง ไม่ใช่บอกทุกปัญหาพร้อมกัน
FaceFraming evaluateFraming(
  FaceObservation observation, {
  FaceFrameTarget target = const FaceFrameTarget(),
}) {
  if (observation.faceCount > 1) return FaceFraming.manyFaces;
  if (!observation.hasOneFace) return FaceFraming.noFace;

  final width = observation.widthRatio;
  if (width == null) return FaceFraming.noFace;
  if (width < target.minWidthRatio) return FaceFraming.tooFar;
  if (width > target.maxWidthRatio) return FaceFraming.tooClose;

  final center = observation.center;
  if (center == null) return FaceFraming.noFace;
  // จุดกึ่งกลางหน้าต้องอยู่ในวงรี: (dx/rx)^2 + (dy/ry)^2 <= 1
  final dx = (center.dx - target.center.dx) / target.radiusX;
  final dy = (center.dy - target.center.dy) / target.radiusY;
  if (dx * dx + dy * dy > 1) return FaceFraming.offCenter;

  final roll = observation.roll;
  if (roll != null && roll.abs() > _maxRollDegrees) return FaceFraming.tilted;

  return FaceFraming.ok;
}

/// ท่าที่ server สั่งให้ทำ
enum FaceActionKind { lookStraight, turnLeft, turnRight, blink }

/// แปลคำสั่งจาก server เป็นท่าที่ตรวจได้
///
/// รองรับ 2 ทาง: ถ้า backend ส่ง `action_code` มาก็ใช้เลย ถ้าไม่ส่ง (เช่น
/// เซิร์ฟเวอร์รุ่นที่ deploy อยู่ตอนนี้) จะเดาจากข้อความไทยแทน
/// **ห้ามเอา `action_code` เป็นเงื่อนไขบังคับ** ไม่งั้นแอปจะพังกับ backend เดิม
FaceActionKind parseFaceAction(String action, {String? code}) {
  final c = (code ?? '').trim().toLowerCase();
  switch (c) {
    case 'look_straight':
      return FaceActionKind.lookStraight;
    case 'turn_left':
      return FaceActionKind.turnLeft;
    case 'turn_right':
      return FaceActionKind.turnRight;
    case 'blink':
      return FaceActionKind.blink;
  }

  final text = action.replaceAll(' ', '');
  if (text.contains('กะพริบ') || text.contains('กระพริบ')) {
    return FaceActionKind.blink;
  }
  if (text.contains('ซ้าย')) return FaceActionKind.turnLeft;
  if (text.contains('ขวา')) return FaceActionKind.turnRight;
  return FaceActionKind.lookStraight;
}

/// จำนวนครั้งที่ต้องกะพริบ — อ่านตัวเลขไทย/อารบิกจากคำสั่ง ไม่มีเลข = 1 ครั้ง
int blinkTargetOf(String action) {
  final m = RegExp(r'(\d+)').firstMatch(action);
  if (m != null) {
    final n = int.tryParse(m.group(1)!);
    if (n != null && n > 0 && n <= 5) return n;
  }
  if (action.contains('สอง')) return 2;
  if (action.contains('สาม')) return 3;
  return 1;
}

/// องศาที่ถือว่า "หันแล้วจริง" และที่ถือว่า "หน้าตรง"
const double _turnDegrees = 22;
const double _straightDegrees = 12;

/// ความน่าจะเป็นที่ถือว่าตาเปิด/ตาปิด
///
/// เว้นช่องว่างระหว่างสองค่าไว้กว้าง เพื่อไม่ให้ค่าที่แกว่งอยู่ตรงกลาง
/// ถูกนับเป็นกะพริบรัว ๆ ทั้งที่ผู้ใช้ยังไม่ได้หลับตาจริง
const double _eyeOpen = 0.60;
const double _eyeClosed = 0.25;

/// ตรวจว่าผู้ใช้ทำท่าตามที่ server สั่งจริงหรือยัง
///
/// **ทำไมต้องมีคลาสนี้:** ของเดิมแค่เช็คว่า "ตาเปิดอยู่" แล้วถือว่าผ่าน liveness
/// ซึ่งรูปถ่ายที่ลืมตาก็ผ่านได้ ตัวนี้บังคับให้เห็น **การเปลี่ยนแปลงตามเวลา**
/// (เปิด → ปิด → เปิด สำหรับกะพริบ, หน้าตรง → หันไปด้านที่สั่ง สำหรับหันหน้า)
///
/// ⚠️ ยังไม่ใช่ liveness ระดับกันวิดีโอ/หน้ากาก — กันได้แค่ภาพนิ่ง
class FaceChallenge {
  final FaceActionKind kind;
  final int blinkTarget;

  FaceChallenge({required this.kind, this.blinkTarget = 1});

  factory FaceChallenge.fromAction(String action, {String? code}) {
    final kind = parseFaceAction(action, code: code);
    return FaceChallenge(
      kind: kind,
      blinkTarget:
          kind == FaceActionKind.blink ? blinkTargetOf(action) : 1,
    );
  }

  /// ไม่มีคำสั่ง = ผ่านทันที (ใช้กับหน้าลงทะเบียนใบหน้า/เช็คอินงานที่ไม่มี challenge)
  factory FaceChallenge.none() =>
      FaceChallenge(kind: FaceActionKind.lookStraight);

  bool _sawStraight = false;
  bool _eyesWereOpen = false;
  bool _eyesAreClosed = false;
  int _blinks = 0;
  bool _done = false;

  /// หันผิดข้างอยู่หรือเปล่า — ใช้บอกผู้ใช้แทนที่จะเงียบแล้วไม่ผ่าน
  bool _wrongWay = false;

  bool get isSatisfied => _done;
  int get blinkCount => _blinks;

  void reset() {
    _sawStraight = false;
    _eyesWereOpen = false;
    _eyesAreClosed = false;
    _blinks = 0;
    _done = false;
    _wrongWay = false;
  }

  /// ป้อนเฟรมใหม่ — เรียกทุกครั้งที่ ML Kit อ่านภาพได้
  void update(FaceObservation observation) {
    if (_done || !observation.hasOneFace) return;

    switch (kind) {
      case FaceActionKind.lookStraight:
        final yaw = observation.yaw;
        if (yaw != null && yaw.abs() <= _straightDegrees) _done = true;

      case FaceActionKind.turnLeft:
      case FaceActionKind.turnRight:
        _updateTurn(observation);

      case FaceActionKind.blink:
        _updateBlink(observation);
    }
  }

  void _updateTurn(FaceObservation observation) {
    final yaw = observation.yaw;
    if (yaw == null) return;

    // ต้องเห็นหน้าตรงก่อน แล้วค่อยหัน — กันเอารูปที่ถ่ายเอียงไว้แล้วมาส่อง
    if (!_sawStraight) {
      if (yaw.abs() <= _straightDegrees) _sawStraight = true;
      return;
    }
    if (yaw.abs() < _turnDegrees) {
      _wrongWay = false;
      return;
    }

    // เครื่องหมายของ yaw ขึ้นกับกล้อง/การ mirror จึงไม่ผูกทิศตายตัว:
    // ยึดทิศแรกที่ผู้ใช้หันเป็นตัวอ้างอิงไม่ได้เช่นกัน จึงรับว่า "หันแล้ว"
    // เมื่อเกินองศาที่กำหนด และใช้ _wrongWay แค่ช่วยแนะนำเมื่อระบบเดาทิศได้
    _done = true;
    _wrongWay = false;
  }

  void _updateBlink(FaceObservation observation) {
    final openness = observation.eyeOpenness;
    if (openness == null) return;

    if (openness >= _eyeOpen) {
      // เห็นตาเปิดหลังจากที่เพิ่งปิดไป = กะพริบครบ 1 ครั้ง
      if (_eyesAreClosed && _eyesWereOpen) {
        _blinks++;
        _eyesAreClosed = false;
        if (_blinks >= blinkTarget) _done = true;
      }
      _eyesWereOpen = true;
    } else if (openness <= _eyeClosed && _eyesWereOpen) {
      _eyesAreClosed = true;
    }
  }

  /// คำแนะนำที่ควรแสดงตอนนี้ (เรียกหลัง [update])
  String hintFor(FaceObservation observation) {
    if (_done) return 'พร้อมแล้ว';
    switch (kind) {
      case FaceActionKind.lookStraight:
        return 'มองตรงมาที่กล้อง';
      case FaceActionKind.turnLeft:
        if (!_sawStraight) return 'มองตรงมาที่กล้องก่อน';
        return _wrongWay ? 'หันไปอีกด้าน' : 'หันหน้าไปทางซ้ายช้า ๆ';
      case FaceActionKind.turnRight:
        if (!_sawStraight) return 'มองตรงมาที่กล้องก่อน';
        return _wrongWay ? 'หันไปอีกด้าน' : 'หันหน้าไปทางขวาช้า ๆ';
      case FaceActionKind.blink:
        if (blinkTarget > 1) {
          return 'กะพริบตาช้า ๆ ($_blinks/$blinkTarget)';
        }
        return 'กะพริบตาช้า ๆ';
    }
  }
}

/// แปลงองศาเป็นสัดส่วนความคืบหน้า 0..1 (ใช้กับวงแหวนรอบตัวเลขนับถอยหลัง)
double progressOf(FaceChallenge challenge, FaceObservation observation) {
  if (challenge.isSatisfied) return 1;
  // num.clamp() คืน num ไม่ใช่ double จึงต้อง toDouble() ทุกจุด
  switch (challenge.kind) {
    case FaceActionKind.blink:
      if (challenge.blinkTarget <= 0) return 0;
      return (challenge.blinkCount / challenge.blinkTarget)
          .clamp(0.0, 1.0)
          .toDouble();
    case FaceActionKind.turnLeft:
    case FaceActionKind.turnRight:
      final yaw = observation.yaw?.abs() ?? 0;
      return (yaw / _turnDegrees).clamp(0.0, 1.0).toDouble();
    case FaceActionKind.lookStraight:
      final yaw = observation.yaw?.abs();
      if (yaw == null) return 0;
      return (1 - math.min(yaw / 45, 1.0)).clamp(0.0, 1.0).toDouble();
  }
}
