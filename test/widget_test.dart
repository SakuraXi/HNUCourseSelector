import 'package:flutter_test/flutter_test.dart';

import 'package:hnu_course_selector/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HnuCourseSelectorApp());
    await tester.pump();
    expect(find.text('海大抢课助手'), findsWidgets);
  });
}
