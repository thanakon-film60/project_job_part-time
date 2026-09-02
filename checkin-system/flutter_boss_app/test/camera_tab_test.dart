import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thanakon_box_boss/models/camera.dart';
import 'package:thanakon_box_boss/screens/tabs/camera_tab.dart';
import 'package:thanakon_box_boss/services/api_service.dart';

/// JPEG 1x1 จริง — ต้องเป็น JPEG จริงเพราะ ApiService ตรวจลายเซ็น 0xFFD8
/// และ Flutter ต้อง decode ได้จริงตอนวาดลงจอ
final Uint8List jpegPixel = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a'
  'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAA'
  'AAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==',
);

/// เซิร์ฟเวอร์ปลอมที่นับได้ว่าแอปยิงมากี่ครั้ง และสั่งให้ตอบพังได้ตามต้องการ
class _FakeCameraServer {
  int statusCalls = 0;
  int snapshotCalls = 0;
  int ptzCalls = 0;

  /// เวลาที่คำขอ /camera/ptz ถูกยิงเข้ามา พร้อม duration_ms ที่แอปขอ
  final List<int> ptzDurations = [];

  bool reachable = true;
  bool failSnapshots = false;
  int snapshotAgeMs = 0;

  Future<_FakeResponse> handle(String method, Uri uri, String? body) async {
    final path = uri.path;

    if (path == '/camera/status') {
      statusCalls++;
      return _FakeResponse.json(200, {
        'enabled': true,
        'reachable': reachable,
        'host': '192.168.1.101',
        'message': reachable ? 'พร้อมใช้งาน' : 'เชื่อมต่อกล้องไม่ได้',
        'model': 'cloudCam',
        'firmware': '43.4.0.0',
        'home_supported': true,
        'audio_supported': false,
        'talkback_supported': false,
      });
    }

    if (path == '/camera/snapshot') {
      snapshotCalls++;
      if (failSnapshots) {
        return _FakeResponse.json(502, {'detail': 'ดึงภาพจากกล้องไม่สำเร็จ'});
      }
      return _FakeResponse.jpeg(jpegPixel, snapshotAgeMs);
    }

    if (path == '/camera/ptz') {
      ptzCalls++;
      final decoded = jsonDecode(body ?? '{}') as Map<String, dynamic>;
      ptzDurations.add((decoded['duration_ms'] as num?)?.toInt() ?? 0);
      return _FakeResponse.json(200, {'ok': true, 'action': decoded['action']});
    }

    return _FakeResponse.json(404, {'detail': 'not found'});
  }
}

class _FakeResponse {
  final int status;
  final List<int> body;
  final Map<String, String> headers;

  _FakeResponse(this.status, this.body, this.headers);

  factory _FakeResponse.json(int status, Object data) => _FakeResponse(
        status,
        utf8.encode(jsonEncode(data)),
        {'content-type': 'application/json'},
      );

  factory _FakeResponse.jpeg(Uint8List bytes, int ageMs) => _FakeResponse(
        200,
        bytes,
        {
          'content-type': 'image/jpeg',
          'x-snapshot-age-ms': '$ageMs',
        },
      );
}

// ---------------------------------------------------------------------------
// ต่อสาย dart:io HttpClient เข้ากับเซิร์ฟเวอร์ปลอมข้างบน
// (package:http วิ่งผ่าน HttpClient จึงดักได้ที่ชั้นนี้ชั้นเดียว)
//
// ตัวปลอมพวกนี้ต้องรองรับเท่าที่ IOClient เรียกจริง: ตั้ง header, ส่ง body
// ผ่าน addStream/close แล้วอ่าน response กลับ ส่วนที่เหลือปล่อยผ่านได้
// ---------------------------------------------------------------------------

class _FakeHttpOverrides extends HttpOverrides {
  final _FakeCameraServer server;
  _FakeHttpOverrides(this.server);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(server);
}

/// เมธอด/พร็อพเพอร์ตี้ที่ไม่ได้ใช้ให้เงียบไว้ ไม่ใช่โยน NoSuchMethodError
mixin _Lenient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClient with _Lenient implements HttpClient {
  final _FakeCameraServer server;
  _FakeHttpClient(this.server);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(server, method, url);

  @override
  void close({bool force = false}) {}
}

class _FakeRequest with _Lenient implements HttpClientRequest {
  final _FakeCameraServer server;
  @override
  final String method;
  @override
  final Uri uri;

  final _body = BytesBuilder();

  _FakeRequest(this.server, this.method, this.uri);

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void add(List<int> data) => _body.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final bytes = _body.takeBytes();
    final res = await server.handle(
      method,
      uri,
      bytes.isEmpty ? null : utf8.decode(bytes),
    );
    return _FakeResponseStream(res);
  }

  @override
  Future<HttpClientResponse> get done => close();
}

class _FakeHeaders with _Lenient implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = ['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');

  @override
  void remove(String name, Object value) => _values.remove(name.toLowerCase());

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  String? value(String name) => _values[name.toLowerCase()]?.first;

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  int contentLength = -1;

  @override
  ContentType? contentType;

  @override
  bool chunkedTransferEncoding = false;

  @override
  bool persistentConnection = true;
}

class _FakeResponseStream extends Stream<List<int>>
    with _Lenient
    implements HttpClientResponse {
  final _FakeResponse res;
  _FakeResponseStream(this.res);

  @override
  int get statusCode => res.status;

  @override
  int get contentLength => res.body.length;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpHeaders get headers {
    final h = _FakeHeaders();
    res.headers.forEach(h.set);
    return h;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(res.body).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

// ---------------------------------------------------------------------------

/// วางแท็บกล้องไว้ใน TickerMode เพื่อจำลอง "แท็บนี้ถูกเปิดดูอยู่หรือถูกซ่อน"
/// เหมือนที่ app_shell ทำกับ IndexedStack
Widget host({required bool visible}) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: const CameraTab(),
        ),
      ),
    );

/// ปล่อยให้คำขอที่ค้างอยู่เดินจนจบ
///
/// pump() เปล่าๆ ไม่พอ เพราะลูปดึงภาพนัดรอบถัดไปด้วย Timer ซึ่งต้องมีเวลา
/// เดินจริงในนาฬิกาจำลองของเทสต์ถึงจะทำงาน
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late _FakeCameraServer server;

  setUp(() async {
    server = _FakeCameraServer();
    HttpOverrides.global = _FakeHttpOverrides(server);

    // ล็อกอินค้างไว้ให้ ApiService ยอมยิงคำขอ (ไม่งั้นโดนตีตกที่ ensureSession)
    // คีย์ต้องมี 'flutter.' นำหน้า — เป็นรูปแบบที่ SharedPreferences เก็บจริง
    SharedPreferences.setMockInitialValues({
      'flutter.token': 'test-token',
      'flutter.session_ends_at':
          DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
    });
    await ApiService.loadToken();

    // แคชรูปของ Flutter ใช้ร่วมกันทั้งกระบวนการ ล้างก่อนทุกเทสต์
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('เปิดแท็บแล้วได้ภาพจากกล้องขึ้นจอ', (tester) async {
    await tester.pumpWidget(host(visible: true));
    await settle(tester);         // ให้ /camera/status และ /camera/snapshot ตอบ

    expect(server.statusCalls, 1);
    expect(server.snapshotCalls, greaterThanOrEqualTo(1));
    expect(find.text('LIVE'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('สลับไปแท็บอื่นแล้วหยุดดึงภาพ กลับมาแล้วดึงต่อ', (tester) async {
    await tester.pumpWidget(host(visible: true));
    await settle(tester);

    // ปล่อยให้ดึงภาพไปสัก 3 วินาที
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    final whileVisible = server.snapshotCalls;
    expect(whileVisible, greaterThanOrEqualTo(3));

    // ผู้ใช้สลับไปแท็บอื่น — IndexedStack ยังเก็บแท็บนี้ไว้ แต่ต้องหยุดยิง
    await tester.pumpWidget(host(visible: false));
    await settle(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(
      server.snapshotCalls,
      whileVisible,
      reason: 'แท็บที่ถูกซ่อนต้องไม่ดึงภาพต่อ',
    );

    // กลับมาที่แท็บกล้อง ต้องดึงต่อเอง
    await tester.pumpWidget(host(visible: true));
    await settle(tester);
    expect(server.snapshotCalls, greaterThan(whileVisible));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ภาพเปลี่ยนทุกวินาทีแล้วแคชรูปต้องไม่บวม', (tester) async {
    await tester.pumpWidget(host(visible: true));
    await settle(tester);

    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    expect(server.snapshotCalls, greaterThanOrEqualTo(20));
    // ทุกเฟรมที่ผ่านไปต้องถูกไล่ออกจากแคช เหลือแค่เฟรมที่กำลังโชว์
    expect(
      PaintingBinding.instance.imageCache.liveImageCount,
      lessThanOrEqualTo(2),
      reason: 'เฟรมเก่าต้องถูก evict ไม่งั้นแคชโตวินาทีละภาพ',
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ภาพหลุดแล้วถอยจังหวะ ไม่ยิงรัวเท่าเดิม', (tester) async {
    await tester.pumpWidget(host(visible: true));
    await settle(tester);

    server.failSnapshots = true;
    final before = server.snapshotCalls;

    // 10 วินาทีนี้ ถ้าไม่มีการถอยจังหวะจะยิงราว 10 ครั้ง
    // มีการถอย (2→4→8) จะเหลือแค่ไม่กี่ครั้ง
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    final attempts = server.snapshotCalls - before;
    expect(attempts, lessThan(7), reason: 'ต้องถอยจังหวะเมื่อดึงภาพไม่ผ่าน');
    expect(attempts, greaterThan(0), reason: 'แต่ต้องยังลองใหม่อยู่');

    // ภาพเดิมต้องยังอยู่บนจอ ไม่ใช่จอดำ
    expect(find.text('ภาพสะดุด — โชว์ภาพล่าสุดไว้ กำลังลองใหม่'), findsOneWidget);

    // กล้องกลับมา -> ต้องกลับไปยิงถี่เหมือนเดิม
    server.failSnapshots = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    final recovered = server.snapshotCalls;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(
      server.snapshotCalls - recovered,
      greaterThanOrEqualTo(4),
      reason: 'กล้องกลับมาแล้วต้องกลับไปวินาทีละครั้ง',
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ลากนิ้วบนภาพขณะที่ภาพรีเฟรชกลางคัน ระยะลากต้องไม่หาย',
      (tester) async {
    await tester.pumpWidget(host(visible: true));
    await settle(tester);

    final image = find.byType(Image);
    expect(image, findsOneWidget);

    // ลากยาวไปทางขวา โดยมีภาพใหม่เข้ามาแทรกกลางการลาก (จุดที่เคยพัง:
    // ตัวนับระยะเคยอยู่ใน build จึงถูกล้างทุกครั้งที่เฟรมเปลี่ยน)
    final start = tester.getCenter(image);
    final gesture = await tester.startGesture(start);
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();     // ปล่อยให้เฟรมใหม่ขึ้นจอระหว่างลาก
    }
    await gesture.up();
    await settle(tester);

    expect(server.ptzCalls, 1, reason: 'ลากครบระยะแล้วต้องสั่งกล้อง 1 ครั้ง');

    // ลากรวม 240px (ส่วนแรกราว 40px ถูกกินไปกับระยะ slop ของ pan gesture)
    // เหลือเข้าตัวนับราว 200px -> ~800ms
    //
    // ถ้าตัวนับถูกล้างทุกครั้งที่เฟรมเปลี่ยน (บั๊กเดิม) จะเหลือแค่ก้าวสุดท้าย
    // 30px -> 120ms ซึ่งถูกดันขึ้นเป็น 300ms ด้วย clamp ขั้นต่ำ
    // ค่ามากกว่า 300 จึงเป็นหลักฐานว่าระยะถูกสะสมข้ามเฟรมจริง
    expect(server.ptzDurations.single, greaterThan(500),
        reason: 'ระยะลากต้องสะสมข้ามเฟรม ไม่ใช่เหลือแค่ก้าวสุดท้าย');

    await tester.pump(const Duration(seconds: 5));
  });

  test('CameraFrame บอกได้ว่ากำลังดูภาพสดหรือภาพค้าง', () {
    final empty = Uint8List(0);
    expect(CameraFrame(empty, Duration.zero).isStale, isFalse);
    expect(
      CameraFrame(empty, const Duration(milliseconds: 900)).isStale,
      isFalse,
    );
    expect(CameraFrame(empty, const Duration(seconds: 5)).isStale, isTrue);
  });
}
