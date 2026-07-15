import 'package:clipshot_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example starts without invoking native extraction', (
    tester,
  ) async {
    await tester.pumpWidget(const ClipshotExampleApp());
    expect(find.text('Clipshot example'), findsWidgets);
  });
}
