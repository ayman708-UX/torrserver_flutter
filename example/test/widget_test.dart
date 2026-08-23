import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('App renders home page with TorrServer stopped initially',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TorrServerExampleApp());

    expect(find.text('TorrServer Flutter'), findsOneWidget);
    expect(find.text('TorrServer stopped'), findsOneWidget);
    expect(find.text('Start Server'), findsOneWidget);
  });
}
