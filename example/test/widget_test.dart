import 'package:clipshot_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows extraction controls', (tester) async {
    await tester.pumpWidget(const ClipshotExampleApp());
    expect(find.text('Extract one'), findsOneWidget);
    expect(find.text('Extract three'), findsOneWidget);
    expect(find.text('Delete thumbnails'), findsOneWidget);
  });
}
