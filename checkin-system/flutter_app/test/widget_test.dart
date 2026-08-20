import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/main.dart';
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
}
