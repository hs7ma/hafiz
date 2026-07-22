import 'package:flutter_test/flutter_test.dart';

import 'package:hafiz_platform/main.dart';

void main() {
  testWidgets('platform app loads login', (WidgetTester tester) async {
    await tester.pumpWidget(const HafizPlatformApp());
    expect(find.text('دخول إدارة المنصة'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });
}
