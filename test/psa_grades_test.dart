import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/widgets/condition_grade_picker.dart';

/// PSA grades run 10 down to 1. The old "≤8" bucket is never offered; it
/// survives only so a row still carrying it reads as itself.
void main() {
  test('PSA grades are 10 to 1, then the legacy bucket', () {
    final psa = CardCondition.values
        .where((c) => c.gradingCompany == 'PSA')
        .map((c) => c.gradeLabel)
        .toList();
    expect(psa, ['10', '9', '8', '7', '6', '5', '4', '3', '2', '1', '≤8']);
  });

  test('new grades round-trip through the stored value', () {
    for (var n = 1; n <= 8; n++) {
      final c = CardConditionX.fromRaw('PSA$n');
      expect(c.raw, 'PSA$n');
      expect(c.short, 'PSA $n');
      expect(c.isGraded, isTrue);
      expect(c.isLegacy, isFalse);
    }
    expect(CardConditionX.fromRaw('PSALOW').isLegacy, isTrue);
  });

  Future<List<String>> openPsaMenu(WidgetTester tester, Widget picker) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: picker),
      ),
    );
    await tester.tap(find.text('PSA'));
    await tester.pumpAndSettle();
    return [
      for (final label in ['10', '1', '≤8'])
        if (find.text(label).evaluate().isNotEmpty) label,
    ];
  }

  testWidgets('the filter offers 10 to 1, without ≤8', (tester) async {
    final shown = await openPsaMenu(
      tester,
      ConditionGradePicker.multi(selected: const {}, onToggled: (_) {}),
    );
    expect(shown, ['10', '1']);
  });

  testWidgets('picking a grade for a bid offers no ≤8 either', (tester) async {
    final shown = await openPsaMenu(
      tester,
      ConditionGradePicker(
        value: CardCondition.nm,
        showAllOption: false,
        onChanged: (_) {},
      ),
    );
    expect(shown, ['10', '1']);
  });
}
