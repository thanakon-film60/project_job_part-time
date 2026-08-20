import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/main.dart';

void main() {
  testWidgets('THANAKON-BOX app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const ThanakonBoxApp());

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });
}
