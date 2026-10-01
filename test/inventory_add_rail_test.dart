import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/inventory_tab.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The add tab's results are pictures, and a card is recognised by its art
/// long before its name is read — so they scroll sideways, as web's do,
/// instead of pushing the drafts table off the screen.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

CardModel _card(int id, String name) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: name,
  expansionCode: 'SV9s',
  packSlug: 'sv9s',
  collectorNumber: '07$id/099',
  rarity: 'AR',
);

Future<void> _search(
  WidgetTester tester, {
  List<CardModel> results = const [],
  List<InventoryEntry> drafts = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        inventoryRecordsProvider.overrideWith((ref) async => []),
        inventoryDraftsProvider.overrideWith((ref) async => drafts),
        cardSearchPickerProvider((
          query: 'pika',
          language: null,
        )).overrideWith((ref) async => results),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: InventoryTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Onto the add tab, then type past the 400ms debounce.
  await tester.tap(find.text('Tambahkan'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, 'pika');
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drafts are a table, editable in place', (tester) async {
    await _search(
      tester,
      results: const [],
      drafts: [
        InventoryEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          quantity: 3,
          unitPrice: 0,
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );

    // Every column web's table declares, in its order.
    for (final header in [
      'Status',
      'Gambar',
      'Nama Kartu',
      'Ekspansi',
      'Nomor',
      'Kelangkaan',
      'Jumlah',
      'Harga Satuan',
      'Harga Total',
      'Catatan',
    ]) {
      expect(find.text(header), findsOneWidget, reason: '$header is missing');
    }

    // The row carries its card, its quantity, and a total that waits for a
    // price before it says anything.
    expect(find.text('Caterpie'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('–'), findsWidgets);

    // And the two bulk actions above it.
    expect(find.text('Hapus Semua'), findsOneWidget);
    expect(find.text('Simpan Semua'), findsOneWidget);
  });

  testWidgets('the settings button hides a column', (tester) async {
    await _search(
      tester,
      results: const [],
      drafts: [
        InventoryEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          quantity: 1,
          unitPrice: 0,
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );

    await tester.tap(find.byIcon(LucideIcons.settings2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kelangkaan').last);
    await tester.pumpAndSettle();

    expect(find.text('Kelangkaan'), findsNothing);
    // What the table is for stays put.
    expect(find.text('Nama Kartu'), findsOneWidget);
  });

  testWidgets('results scroll sideways, not down', (tester) async {
    await _search(
      tester,
      results: [_card(1, 'Pikachu'), _card(2, 'Pikachu ex')],
    );

    final rail = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    expect(rail, findsOneWidget);
    expect(find.text('Pikachu'), findsOneWidget);
    // The tile fits the height the rail reserves for it.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card already staged carries its count', (tester) async {
    await _search(
      tester,
      results: [_card(1, 'Pikachu')],
      drafts: [
        InventoryEntry(
          id: -1,
          card: _card(1, 'Pikachu'),
          quantity: 2,
          unitPrice: 1000,
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );

    expect(find.text('2'), findsWidgets);
  });
}
