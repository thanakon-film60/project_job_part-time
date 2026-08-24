import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/main.dart';
import 'package:thanakon_box_checkin/services/api_service.dart';
import 'package:thanakon_box_checkin/services/location_service.dart';

void main() {
  testWidgets('THANAKON-BOX app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const ThanakonBoxApp());

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });

  test('checkout geofence ignores offices that disallow checkout', () {
    final (trackingOffice, _, trackingWithin) =
        LocationService.nearestOffice(13.8865664, 100.5066278);
    expect(trackingOffice.name, 'ถึงบ้านแล้ว');
    expect(trackingOffice.allowCheckout, isFalse);
    expect(trackingWithin, isTrue);

    final (workOffice, _, workWithin) = LocationService.nearestOffice(
      13.8865664,
      100.5066278,
      workOnly: true,
    );
    expect(workOffice.allowCheckout, isTrue);
    expect(workOffice.name, isNot('ถึงบ้านแล้ว'));
    expect(workWithin, isFalse);
  });

  test('server timestamps without timezone are treated as UTC', () {
    final parsed = ApiService.parseServerTimestamp('2026-08-21T04:41:00');

    expect(parsed, isNotNull);
    expect(parsed!.isUtc, isTrue);
    expect(parsed.toUtc().hour, 4);
    expect(parsed.toUtc().minute, 41);
  });

  test('server timestamps with timezone keep their absolute instant', () {
    final parsed = ApiService.parseServerTimestamp('2026-08-21T11:41:00+07:00');

    expect(parsed, isNotNull);
    expect(parsed!.toUtc().hour, 4);
    expect(parsed.toUtc().minute, 41);
  });
}
