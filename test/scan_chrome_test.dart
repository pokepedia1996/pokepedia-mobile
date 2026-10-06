import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/scanner/presentation/widgets/scan_price_burst.dart';
import 'package:pokepedia_mobile/features/scanner/presentation/widgets/scan_status_pill.dart';
import 'package:pokepedia_mobile/features/scanner/presentation/widgets/scanner_top_bar.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(backgroundColor: Colors.black, body: child),
    ),
  );
  await tester.pump();
}

/// The scanner's chrome is the only thing telling a user whether anything is
/// happening — the detector runs eight times a second and says nothing on its
/// own. The app showed three states where web shows five, so the whole
/// tracking half read as "ready" from start to finish.
void main() {
  group('the status pill', () {
    testWidgets('speaks for every stage, in web\'s words', (tester) async {
      const expected = {
        ScanPillStatus.searching: 'Mencari kartu...',
        ScanPillStatus.locking: 'Mengunci...',
        ScanPillStatus.done: 'Kartu terbaca, angkat kartu',
        ScanPillStatus.capturing: 'Memindai...',
        ScanPillStatus.processing: 'Memproses...',
        ScanPillStatus.paused: 'Dijeda',
      };

      for (final entry in expected.entries) {
        await _pump(tester, ScanStatusPill(status: entry.key));
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: '${entry.key} should read "${entry.value}"',
        );
      }
    });

    testWidgets('only the waiting states spin', (tester) async {
      // A spinner while tracking would claim work is in flight when the
      // scanner is simply looking.
      await _pump(tester, const ScanStatusPill(status: ScanPillStatus.locking));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _pump(
        tester,
        const ScanStatusPill(status: ScanPillStatus.processing),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('the price burst', () {
    testWidgets('shows the price large once there is one', (tester) async {
      await _pump(tester, const ScanPriceBurst(visible: true, price: 240000));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Rp240.000'));
      // Readable at arm's length, which is where the phone is held.
      expect(text.style?.fontSize, greaterThan(30));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('says nothing while the price is still in flight', (
      tester,
    ) async {
      // The price fetch is off the scan's critical path, so a match can land
      // before it. "Rp-" at display size would be worse than silence.
      await _pump(tester, const ScanPriceBurst(visible: true, price: null));
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('cannot swallow a tap meant for the preview', (tester) async {
      await _pump(tester, const ScanPriceBurst(visible: true, price: 1000));

      // Scaffold and the animations contribute their own, so this asks for
      // the one wrapping the burst rather than counting them.
      final guard = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(ScanPriceBurst),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(guard.ignoring, isTrue);
    });
  });

  group('the top bar', () {
    Widget bar({
      bool paused = false,
      bool torchSupported = true,
      bool soundOn = true,
      VoidCallback? onTogglePause,
      VoidCallback? onToggleTorch,
      VoidCallback? onToggleSound,
    }) => Stack(
      children: [
        ScannerTopBar(
          language: CardLanguage.values.first,
          onLanguageChanged: (_) {},
          busy: false,
          paused: paused,
          onTogglePause: onTogglePause ?? () {},
          torchSupported: torchSupported,
          torchOn: false,
          onToggleTorch: onToggleTorch ?? () {},
          soundOn: soundOn,
          onToggleSound: onToggleSound ?? () {},
          onClose: () {},
        ),
      ],
    );

    testWidgets('carries web\'s controls: back, pause, torch, sound', (
      tester,
    ) async {
      var paused = 0, sound = 0;
      await _pump(
        tester,
        bar(onTogglePause: () => paused++, onToggleSound: () => sound++),
      );

      expect(find.bySemanticsLabel('Kembali'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Jeda pemindaian'));
      await tester.tap(find.bySemanticsLabel('Matikan suara'));
      expect(paused, 1);
      expect(sound, 1);
      for (final lang in CardLanguage.values) {
        expect(find.text(lang.shortLabel), findsOneWidget);
      }
    });

    testWidgets('labels flip with state', (tester) async {
      await _pump(tester, bar(paused: true, soundOn: false));
      expect(find.bySemanticsLabel('Lanjutkan pemindaian'), findsOneWidget);
      expect(find.bySemanticsLabel('Nyalakan suara'), findsOneWidget);
    });

    testWidgets('an unsupported torch stays, but does nothing', (tester) async {
      var torch = 0;
      await _pump(
        tester,
        bar(torchSupported: false, onToggleTorch: () => torch++),
      );
      await tester.tap(find.bySemanticsLabel('Nyalakan senter'));
      expect(torch, 0);
    });
  });
}
