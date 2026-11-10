import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/rupiah_prefix.dart';

void main() {
  Future<void> pump(WidgetTester tester, TextEditingController controller) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixIcon: RupiahPrefix(),
                prefixIconConstraints: RupiahPrefix.constraints,
                hintText: '0',
              ),
            ),
          ),
        ),
      );

  testWidgets('shows on an empty, unfocused field', (tester) async {
    await pump(tester, TextEditingController());
    expect(find.text('Rp'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Rp')).dx, 18);
  });

  testWidgets('sits on the line of the digits it prefixes', (tester) async {
    await pump(tester, TextEditingController(text: '200.000'));
    final rp = tester.getRect(find.text('Rp'));
    final input = tester.getRect(find.byType(EditableText));
    expect(rp.center.dy, closeTo(input.center.dy, 0.5));
    expect(input.left, greaterThan(rp.right));
  });
}
