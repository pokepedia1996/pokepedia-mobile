import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/inventory_tab.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Database and Aktivitas are tables on web, and they are tables here: the
/// same columns, in the same order, so a collector reading one tab already
/// knows how to read the other.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

CardModel _card(int id, String name) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: name,
  expansionCode: 'sv9s',
  packSlug: 'sv9s',
  collectorNumber: '00$id/099',
  rarity: 'AR',
);

Future<void> _open(
  WidgetTester tester,
  String tab, {
  List<InventoryEntry> records = const [],
  List<InventoryActivityEntry> activity = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        inventoryRecordsProvider.overrideWith((ref) async => records),
        inventoryDraftsProvider.overrideWith((ref) async => []),
        inventoryActivityProvider.overrideWith((ref) async => activity),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: InventoryTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the database tab is web\'s table', (tester) async {
    await _open(
      tester,
      'Database',
      records: [
        InventoryEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          quantity: 2,
          unitPrice: 5000,
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );

    for (final header in [
      'Gambar',
      'Nama Kartu',
      'Ekspansi',
      'Nomor',
      'Kelangkaan',
      'Jumlah',
      'Harga Satuan',
      'Harga Total',
    ]) {
      expect(find.text(header), findsOneWidget, reason: '$header is missing');
    }

    expect(find.text('Caterpie'), findsOneWidget);
    expect(find.text('SV9S'), findsOneWidget);
    expect(find.text('001/099'), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Unit price, then the two copies together.
    expect(find.text('Rp5.000'), findsOneWidget);
    expect(find.text('Rp10.000'), findsOneWidget);
  });

  testWidgets('the activity tab is web\'s table', (tester) async {
    await _open(
      tester,
      'Aktivitas',
      activity: [
        InventoryActivityEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          action: InventoryActivityAction.addedIn,
          quantity: 3,
          unitPrice: 2000,
          createdAt: DateTime(2026, 9, 13, 14, 30),
        ),
        InventoryActivityEntry(
          id: 2,
          card: _card(2, 'Metapod'),
          action: InventoryActivityAction.removedOut,
          quantity: 1,
          unitPrice: 1000,
          createdAt: DateTime(2026, 9, 12, 9, 5),
        ),
      ],
    );

    for (final header in [
      'Tanggal',
      'Aksi',
      'Jumlah',
      'Nama Kartu',
      'Ekspansi',
      'Nomor',
      'Kelangkaan',
      'Harga Satuan',
      'Harga Total',
    ]) {
      expect(find.text(header), findsOneWidget, reason: '$header is missing');
    }

    // When it happened, to the minute, and what it was.
    expect(find.text('13 Sep'), findsOneWidget);
    expect(find.text('14.30'), findsOneWidget);
    expect(find.text('Ditambahkan'), findsOneWidget);
    expect(find.text('Dihapus'), findsOneWidget);

    // Quantity times unit price, per row.
    expect(find.text('Rp6.000'), findsOneWidget);
    expect(find.text('Rp1.000'), findsWidgets);
  });

  testWidgets('both tables scroll sideways', (tester) async {
    await _open(
      tester,
      'Aktivitas',
      activity: [
        InventoryActivityEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          action: InventoryActivityAction.updated,
          quantity: 1,
          unitPrice: 0,
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
