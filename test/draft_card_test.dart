import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/draft_card.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The draft card is where a draft becomes postable: a price, a condition,
/// photos. Each of those has to be reachable from the card itself.
class _FakeRepo extends SellerListingsRepository {
  _FakeRepo._(SupabaseClient c) : super(c);

  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  final writes = <Map<String, Object?>>[];

  @override
  Future<String?> updateDraft(
    int id, {
    int? quantity,
    int? price,
    bool? autoRelist,
    bool? acceptsOffers,
    CardCondition? condition,
  }) async {
    writes.add({'id': id, 'price': price, 'quantity': quantity});
    return null;
  }
}

SellerDraft _draft({
  int? marketPrice,
  bool autoRelist = false,
  bool acceptsOffers = false,
}) => SellerDraft(
  autoRelist: autoRelist,
  acceptsOffers: acceptsOffers,
  id: 1,
  card: CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Pikachu',
    expansionCode: 'CRZ',
    packSlug: 'crz',
    collectorNumber: '160/159',
    rarity: 'Secret Rare',
    marketPrice: marketPrice,
  ),
  condition: CardCondition.nm,
  quantity: 1,
  photoCount: 0,
);

Future<_FakeRepo> _pump(WidgetTester tester, SellerDraft draft) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sellerListingsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DraftCard(
            draft: draft,
            selected: false,
            onToggleSelect: () {},
            onDelete: () {},
            onChanged: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('the market-price button is there when there is a price', (
    tester,
  ) async {
    await _pump(tester, _draft(marketPrice: 45000));

    expect(find.bySemanticsLabel('Pakai harga pasaran'), findsOneWidget);
    // And the placeholder says what it would fill in.
    // "pasaran" stays in the hint: the number is the market's, not one the
    // seller typed, and without the word it reads as a price already set.
    // Spelled the same way the value is, so the two compare directly.
    expect(find.text('Rp45.000 pasaran'), findsOneWidget);
  });

  testWidgets('tapping it fills the price in and writes it', (tester) async {
    final repo = await _pump(tester, _draft(marketPrice: 45000));

    await tester.tap(find.bySemanticsLabel('Pakai harga pasaran'));
    await tester.pump();

    expect(repo.writes, hasLength(1));
    expect(repo.writes.single['price'], 45000);
  });

  testWidgets('the counter and the price sit side by side', (tester) async {
    await _pump(tester, _draft(marketPrice: 45000));

    final jumlah = tester.getTopLeft(find.text('Jumlah'));
    final harga = tester.getTopLeft(find.text('Harga jual'));

    // One row, labels on one line.
    expect(jumlah.dy, harga.dy);
    expect(jumlah.dx, lessThan(harga.dx));

    // And "Harga jual" sits at the left edge of the field it names, not
    // centred over it.
    final field = tester.getTopLeft(find.byType(TextField));
    expect(harga.dx, field.dx);

    // The value inside runs from the same edge.
    expect(
      tester.widget<TextField>(find.byType(TextField)).textAlign,
      TextAlign.start,
    );
  });

  testWidgets('the price field takes the width the counter does not', (
    tester,
  ) async {
    await _pump(tester, _draft(marketPrice: 45000));

    final counter = tester.getSize(find.byType(TextField));
    // Splitting the row by flex gave the stepper a box half again its width
    // and left the price — the longer thing to read, and the thing being
    // decided — in the narrower half.
    expect(counter.width, greaterThan(150));
  });

  testWidgets('the button is there even without a market price', (
    tester,
  ) async {
    await _pump(tester, _draft());

    // Present but dimmed. A button that disappears for some cards reads as
    // a feature this card lacks rather than as a price the cache is missing.
    expect(find.bySemanticsLabel('Pakai harga pasaran'), findsOneWidget);
    expect(find.text('Harga'), findsOneWidget);
  });

  testWidgets('pressing it without a market price says why', (tester) async {
    final repo = await _pump(tester, _draft());

    await tester.tap(find.bySemanticsLabel('Pakai harga pasaran'));
    await tester.pump();

    expect(
      find.text('Belum ada harga pasaran untuk kartu ini'),
      findsOneWidget,
    );
    // And nothing was written.
    expect(repo.writes, isEmpty);
  });

  testWidgets('the switch labels stay on one line', (tester) async {
    await _pump(tester, _draft(marketPrice: 45000));

    // "Perpanjang otomatis" is the long one, and wrapping it cost the card
    // a whole row on every draft in the list.
    for (final label in ['Perpanjang otomatis', 'Terima penawaran']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1, reason: label);
    }

    // Both switch rows share a line with each other, too.
    expect(
      tester.getTopLeft(find.text('Perpanjang otomatis')).dy,
      tester.getTopLeft(find.text('Terima penawaran')).dy,
    );
  });

  testWidgets('the switches sit left, under a rule', (tester) async {
    await _pump(tester, _draft(marketPrice: 45000));

    // A rule separates the fields above from the two standing choices below.
    expect(find.byType(Divider), findsOneWidget);
    final rule = tester.getTopLeft(find.byType(Divider)).dy;
    expect(tester.getTopLeft(find.text('Jumlah')).dy, lessThan(rule));
    expect(
      tester.getTopLeft(find.text('Perpanjang otomatis')).dy,
      greaterThan(rule),
    );

    // The pair starts at the card's left edge, just past the first switch.
    // (Where it *ends* is not assertable here: this harness draws a square
    // fallback font, so the labels measure far wider than on a device and
    // fill their share whatever the layout does.)
    final first = tester.getTopLeft(find.text('Perpanjang otomatis')).dx;
    expect(first, lessThan(60));

    // And the second follows the first rather than being pushed to the far
    // side by an Expanded taking half the card each.
    final firstEnd = tester.getTopRight(find.text('Perpanjang otomatis')).dx;
    final secondStart = tester.getTopLeft(find.text('Terima penawaran')).dx;
    expect(secondStart - firstEnd, lessThan(60));
  });

  testWidgets('the price reads as rupiah, not raw digits', (tester) async {
    final draft = SellerDraft(
      id: 3,
      card: _draft().card,
      condition: CardCondition.nm,
      quantity: 1,
      photoCount: 0,
      price: 1250000,
    );
    await _pump(tester, draft);

    final field = tester.widget<TextField>(find.byType(TextField));
    // Grouped and prefixed: six unseparated digits are not read at a glance,
    // and the hint beside it spells the market price out the same way.
    expect(field.controller!.text, 'Rp1.250.000');
  });

  testWidgets('typing groups the digits as they go in', (tester) async {
    await _pump(tester, _draft(marketPrice: 45000));

    await tester.enterText(find.byType(TextField), '75000');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Rp75.000');
  });

  testWidgets('the camera badge is a control, not a decoration', (
    tester,
  ) async {
    await _pump(tester, _draft(marketPrice: 1000));

    expect(find.bySemanticsLabel('Tambah foto kartu'), findsOneWidget);
    expect(find.byIcon(LucideIcons.camera), findsOneWidget);
  });

  testWidgets('a draft with photos says so with a tick', (tester) async {
    final draft = SellerDraft(
      id: 2,
      card: _draft().card,
      condition: CardCondition.nm,
      quantity: 1,
      photoCount: 2,
      photoUrls: const ['a', 'b'],
    );
    await _pump(tester, draft);

    expect(find.bySemanticsLabel('Ubah foto kartu'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.camera), findsNothing);
  });

  testWidgets('a switch set from the bulk menu shows on the card', (
    tester,
  ) async {
    await _pump(tester, _draft());
    expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isFalse);

    // What a bulk apply looks like from here: the list re-reads and hands
    // the card the same draft with the flag now set. The card kept its own
    // copy of that value and was ignoring the new one.
    await _pump(tester, _draft(autoRelist: true));

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.first.value, isTrue);
    expect(switches.last.value, isFalse);
  });

  testWidgets('both switches follow, not just the first', (tester) async {
    await _pump(tester, _draft());
    await _pump(tester, _draft(acceptsOffers: true));

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.first.value, isFalse);
    expect(switches.last.value, isTrue);
  });

  testWidgets('a toggle made here is not undone by the re-read', (
    tester,
  ) async {
    await _pump(tester, _draft());

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isTrue);

    // The list re-reads before the write has landed, so the draft still
    // says false. The card must not snap back under the seller's finger.
    await _pump(tester, _draft());
    expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isTrue);
  });
}
