import 'package:flutter_test/flutter_test.dart';

import 'package:mardodi_checkin/main.dart';

void main() {
  testWidgets('MARDODI app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const MardodiApp());

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });
}
