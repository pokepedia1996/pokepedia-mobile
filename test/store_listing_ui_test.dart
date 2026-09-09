import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/theme/app_radius.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/core/theme/app_typography.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/features/orders/utils/order_status_display.dart';
import 'package:pokepedia_mobile/shared/widgets/app_search_field.dart';
import 'package:pokepedia_mobile/shared/widgets/inline_pill.dart';
import 'package:pokepedia_mobile/shared/widgets/condition_badge.dart';
import 'package:pokepedia_mobile/shared/widgets/reputation_star.dart';

void main() {
  group('ConditionBadge', () {
    testWidgets('spells the grade out only when asked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ConditionBadge(condition: CardCondition.nm),
                ConditionBadge(condition: CardCondition.nm, full: true),
              ],
            ),
          ),
        ),
      );

      // The thumbnail form stays short — 15 call sites depend on it.
      expect(find.text('NM'), findsOneWidget);
      // The purchase panel spells it out, as web's CONDITION_LABEL does.
      expect(find.text('Near Mint'), findsOneWidget);
    });

    testWidgets('tints per grade only when asked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(
              children: [
                ConditionBadge(
                  key: Key('plain'),
                  condition: CardCondition.nm,
                ),
                ConditionBadge(
                  key: Key('tinted'),
                  condition: CardCondition.nm,
                  colored: true,
                ),
              ],
            ),
          ),
        ),
      );

      BoxDecoration decorationOf(String key) =>
          tester.widget<Container>(
                find.descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(Container),
                ),
              ).decoration!
              as BoxDecoration;

      // Over artwork the pill stays white; in the panel it carries the
      // grade's colour, the way CONDITION_BADGE_CLASSES does.
      expect(decorationOf('plain').color, Colors.white);
      expect(decorationOf('tinted').color, isNot(Colors.white));
    });

    testWidgets('a graded slab keeps its own wording', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConditionBadge(condition: CardCondition.psa10, full: true),
          ),
        ),
      );
      expect(find.text('PSA 10'), findsOneWidget);
    });
  });

  group('button typography', () {
    testWidgets('a styleFrom textStyle must not drop the font', (tester) async {
      // ButtonStyle takes the first non-null textStyle rather than merging
      // them, so a bare `const TextStyle(fontWeight: ...)` override throws
      // away the theme's family and size — Tawar and Keranjang were rendering
      // in the platform default face because of exactly that.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ElevatedButton(
              key: const Key('styled'),
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                textStyle: AppTypography.bodySmSemibold(Colors.white),
              ),
              child: const Text('Tawar'),
            ),
          ),
        ),
      );

      final finder = find.descendant(
        of: find.byKey(const Key('styled')),
        matching: find.byType(Text),
      );
      final style = DefaultTextStyle.of(
        tester.element(finder),
      ).style.merge(tester.widget<Text>(finder).style);

      expect(style.fontFamily, contains('Urbanist'));
      expect(style.fontSize, 14.0);
    });
  });

  group('reputationTier', () {
    test('a new seller is hollow, an established one is filled', () {
      // Web: fill={tier.isNew ? "none" : tier.color}. The old mobile star
      // picked the same outline glyph on both branches, so every seller
      // looked new.
      expect(reputationTier(0).isNew, isTrue);
      expect(reputationTier(9).isNew, isTrue);
      expect(reputationTier(10).isNew, isFalse);
      expect(reputationTier(250000).isNew, isFalse);
    });

    test('the comet trail starts at 10,000', () {
      expect(reputationTier(9999).hasTrail, isFalse);
      expect(reputationTier(10000).hasTrail, isTrue);
      expect(reputationTier(1000000).hasTrail, isTrue);
    });

    test('tier colours follow the web thresholds', () {
      expect(reputationTier(5).color, const Color(0xFFD1D5DB));
      expect(reputationTier(50).color, const Color(0xFF3B82F6));
      expect(reputationTier(1000).color, const Color(0xFFDC2626));
      expect(reputationTier(1000000).color, const Color(0xFFC0C0C0));
    });
  });

  group('AppSearchField', () {
    testWidgets('every search bar wears Beranda\'s pill', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: AppSearchField(hintText: 'Cari kartu...'),
          ),
        ),
      );

      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppSearchField),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;

      // The shape the field is meant to have everywhere: a 40pt pill on the
      // muted fill, not the form decoration the rest of the app's inputs use.
      expect(box.constraints?.maxHeight, 40);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppRadius.full),
      );
      expect(decoration.border, isNotNull);
    });

    testWidgets('the clear button appears with text and reports it', (
      tester,
    ) async {
      String? reported;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AppSearchField(
              hintText: 'Cari',
              controller: controller,
              onChanged: (v) => reported = v,
            ),
          ),
        ),
      );

      expect(find.byTooltip('Hapus'), findsNothing);

      await tester.enterText(find.byType(TextField), 'charizard');
      await tester.pump();
      expect(find.byTooltip('Hapus'), findsOneWidget);

      await tester.tap(find.byTooltip('Hapus'));
      await tester.pump();
      // The callers that used to hand-roll this button all reset their query
      // from onChanged, so clearing has to report an empty string.
      expect(reported, '');
      expect(controller.text, isEmpty);
      expect(find.byTooltip('Hapus'), findsNothing);
    });
  });

  group('in-field scanner', () {
    testWidgets('camera while empty, clear once typing — never both', (
      tester,
    ) async {
      var scans = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AppSearchField(
              hintText: 'Cari kartu...',
              onScan: () => scans++,
            ),
          ),
        ),
      );

      // Web's navbar renders `value ? <X/> : <Camera/>`, so the right edge
      // holds exactly one control at a time.
      expect(find.byIcon(LucideIcons.camera), findsOneWidget);
      expect(find.byTooltip('Hapus'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.camera));
      await tester.pump();
      expect(scans, 1);

      await tester.enterText(find.byType(TextField), 'pikachu');
      await tester.pump();
      expect(find.byIcon(LucideIcons.camera), findsNothing);
      expect(find.byTooltip('Hapus'), findsOneWidget);
    });

    testWidgets('a field with no scanner shows no camera', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AppSearchField(hintText: 'Cari')),
        ),
      );
      expect(find.byIcon(LucideIcons.camera), findsNothing);
    });
  });

  group('status pill tones', () {
    // Web's StatusPill has seven tones; mobile had six and let "Dikirim"
    // borrow `info`, which pushed `info` off blue onto indigo and left
    // `progress` holding blue instead of the brand colour.
    testWidgets('progress is the brand colour, as web\'s bg-primary/10 is', (
      tester,
    ) async {
      late Color progress;
      late Color info;
      late Color shipped;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              progress = toneColor(context, InlinePillTone.progress);
              info = toneColor(context, InlinePillTone.info);
              shipped = toneColor(context, InlinePillTone.shipped);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(progress, AppTheme.light.colorScheme.primary);
      // Three distinct tones, not two colours doing three jobs.
      expect(info, isNot(progress));
      expect(shipped, isNot(info));
      expect(shipped, const Color(0xFF6366F1));
    });

    test('Dalam Proses and Dikirim take the tones web gives them', () {
      expect(describeMatchStatus('in_escrow').tone, InlinePillTone.progress);
      expect(describeMatchStatus('awaiting_shipment').tone,
          InlinePillTone.progress);
      expect(describeMatchStatus('shipped').tone, InlinePillTone.shipped);
      expect(describeMatchStatus('open').tone, InlinePillTone.info);
      expect(describeMatchStatus('refunded').tone, InlinePillTone.info);
    });
  });

  group('pill values match web\'s toneStyles', () {
    testWidgets('progress is primary at 10/100/20, not a shifted red', (
      tester,
    ) async {
      late ({Color background, Color foreground, Color ring}) scheme;
      late Color primary;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              scheme = tonePillColors(context, InlinePillTone.progress);
              primary = Theme.of(context).colorScheme.primary;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // `bg-primary/10 text-primary ring-primary/20`. The label is the brand
      // red itself — the old derivation darkened it by 18% lightness, which
      // is what made it read as a different red from the site's.
      expect(scheme.foreground, primary);
      expect(scheme.background.a, closeTo(0.10, 0.001));
      expect(scheme.ring.a, closeTo(0.20, 0.001));
      expect(scheme.background.r, primary.r);
    });

    testWidgets('danger carries web\'s red-100/700/200, not a tint of error', (
      tester,
    ) async {
      late ({Color background, Color foreground, Color ring}) scheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              scheme = tonePillColors(context, InlinePillTone.danger);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Tailwind v4 red-100 / red-700 / red-200.
      expect(scheme.background, const Color(0xFFFFE2E2));
      expect(scheme.foreground, const Color(0xFFC10007));
      expect(scheme.ring, const Color(0xFFFFC9C9));
    });

    testWidgets('dark uses the 15%/300/30% rule web applies', (tester) async {
      late ({Color background, Color foreground, Color ring}) scheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              scheme = tonePillColors(context, InlinePillTone.success);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // `dark:bg-emerald-500/15 dark:text-emerald-300 dark:ring-emerald-500/30`
      expect(scheme.background.a, closeTo(0.15, 0.001));
      expect(scheme.ring.a, closeTo(0.30, 0.001));
      expect(scheme.foreground, const Color(0xFF5EE9B5));
    });
  });
}
