import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/scanner/utils/auto_capture.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';
import 'package:pokepedia_mobile/shared/widgets/confirm_dialog.dart';

Quad _quad({double dx = 0}) => Quad([
  Point2(dx, 0),
  Point2(dx + 400, 0),
  Point2(dx + 400, 400 / 0.7159),
  Point2(dx, 400 / 0.7159),
]);

/// Scanning the same card twice in a row is usually the scanner firing again
/// on a card still in shot rather than someone holding two copies — but a
/// playset is four of one card, so it is a question, not a refusal.
void main() {
  testWidgets('the prompt names the card and offers both answers', (
    tester,
  ) async {
    var added = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Kartu yang sama terdeteksi',
                description: 'Pikachu baru saja dipindai. Tambahkan lagi?',
                confirmLabel: 'Tambahkan',
                cancelLabel: 'Batalkan',
                destructive: false,
                onConfirm: () async => added = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kartu yang sama terdeteksi'), findsOneWidget);
    expect(find.textContaining('Pikachu baru saja dipindai'), findsOneWidget);

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    expect(added, isFalse, reason: 'declining must not file a copy');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambahkan'));
    await tester.pumpAndSettle();
    expect(added, isTrue);
  });

  test('declining leaves the machine suspended, not re-armed', () {
    // The state the prompt is answered in: the machine has just fired, so it
    // is already suspended until the card moves. Re-arming it on a decline
    // would put the same question back on screen a second later.
    final machine = AutoCaptureMachine();
    final t0 = DateTime(2026, 9, 1, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    machine.tick(_quad(), at(0));
    expect(machine.tick(_quad(), at(400)).action, AutoCaptureAction.capture);

    // Still in shot, still still: no second fire.
    expect(machine.tick(_quad(), at(900)).action, AutoCaptureAction.tracking);
    expect(machine.tick(_quad(), at(1400)).action, AutoCaptureAction.tracking);

    // Moving it far enough is what re-arms — a different card, or the same
    // one deliberately re-presented.
    machine.tick(_quad(dx: 400), at(1500));
    expect(
      machine.tick(_quad(dx: 400), at(1900)).action,
      AutoCaptureAction.capture,
    );
  });
}
