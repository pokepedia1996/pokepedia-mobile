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
  List<InventoryColumn> columns = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        inventoryRecordsProvider.overrideWith((ref) async => records),
        inventoryDraftsProvider.overrideWith(() => _Drafts(const [])),
        inventoryActivityProvider.overrideWith((ref) async => activity),
        inventoryColumnsProvider.overrideWith((ref) async => columns),
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

/// The table is wider than the phone and scrolls sideways; a header past
/// the edge has to be brought into view before it can be tapped.
Future<void> _tapHeader(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Stands in for the drafts notifier with a fixed list.
class _Drafts extends InventoryDraftsNotifier {
  _Drafts(this.drafts);

  final List<InventoryEntry> drafts;

  @override
  Future<List<InventoryEntry>> build() async => drafts;
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
          series: 'Scarlet & Violet',
          notes: 'Binder hijau',
        ),
      ],
    );

    expect(find.text('13 Sep 2026'), findsOneWidget);
    expect(find.text('Scarlet & Violet'), findsOneWidget);
    expect(find.text('Binder hijau'), findsOneWidget);

    for (final header in [
      'Tanggal',
      'Gambar',
      'Nama Kartu',
      'Ekspansi',
      'Nomor',
      'Kelangkaan',
      'Seri',
      'Jumlah',
      'Harga Rata-rata',
      'Harga Total',
      'Catatan',
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
      'Seri',
      'Harga Satuan',
      'Harga Total',
    ]) {
      expect(find.text(header), findsOneWidget, reason: '$header is missing');
    }

    // When it happened, to the minute, and what it was.
    expect(find.text('13 Sep 2026'), findsOneWidget);
    expect(find.text('14.30'), findsOneWidget);
    // Web's words for it.
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);

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

  group('the database table sorts', () {
    final records = [
      InventoryEntry(
        id: 1,
        card: _card(1, 'Caterpie'),
        quantity: 1,
        unitPrice: 9000,
        createdAt: DateTime(2026, 9, 10),
        series: 'Sword & Shield',
        seriesId: 8,
      ),
      InventoryEntry(
        id: 2,
        card: _card(2, 'Metapod'),
        quantity: 5,
        unitPrice: 1000,
        createdAt: DateTime(2026, 9, 12),
        series: 'Scarlet & Violet',
        seriesId: 9,
      ),
      InventoryEntry(
        id: 3,
        card: _card(3, 'Butterfree'),
        quantity: 3,
        unitPrice: 4000,
        createdAt: DateTime(2026, 9, 11),
        series: 'Sun & Moon',
        seriesId: 7,
      ),
    ];

    List<String> order(WidgetTester tester) {
      final names = ['Caterpie', 'Metapod', 'Butterfree'];
      final ys = {for (final n in names) n: tester.getTopLeft(find.text(n)).dy};
      return names..sort((a, b) => ys[a]!.compareTo(ys[b]!));
    }

    testWidgets('newest first until a header is tapped', (tester) async {
      await _open(tester, 'Database', records: records);
      expect(order(tester), ['Metapod', 'Butterfree', 'Caterpie']);
    });

    testWidgets('by name, then reversed on a second tap', (tester) async {
      await _open(tester, 'Database', records: records);

      await _tapHeader(tester, 'Nama Kartu');
      await tester.pumpAndSettle();
      expect(order(tester), ['Butterfree', 'Caterpie', 'Metapod']);

      await _tapHeader(tester, 'Nama Kartu');
      await tester.pumpAndSettle();
      expect(order(tester), ['Metapod', 'Caterpie', 'Butterfree']);
    });

    testWidgets('by quantity and by total, as numbers', (tester) async {
      await _open(tester, 'Database', records: records);

      await _tapHeader(tester, 'Jumlah');
      await tester.pumpAndSettle();
      expect(order(tester), ['Caterpie', 'Butterfree', 'Metapod']);

      // Totals: 9.000, 5.000, 12.000.
      await _tapHeader(tester, 'Harga Total');
      await tester.pumpAndSettle();
      expect(order(tester), ['Metapod', 'Caterpie', 'Butterfree']);
    });

    testWidgets('series in release order, not by name', (tester) async {
      await _open(tester, 'Database', records: records);

      await _tapHeader(tester, 'Seri');
      await tester.pumpAndSettle();
      // Sun & Moon (7), Sword & Shield (8), Scarlet & Violet (9) — which
      // A–Z would have put first.
      expect(order(tester), ['Butterfree', 'Caterpie', 'Metapod']);
    });
  });

  testWidgets('the columns follow the settings kept on web', (tester) async {
    InventoryColumn column(
      String key, {
      bool visible = true,
      bool custom = false,
      String? label,
    }) => InventoryColumn(
      key: key,
      label: label ?? key,
      isVisible: visible,
      isCustom: custom,
      isNumber: false,
    );

    await _open(
      tester,
      'Database',
      records: [
        InventoryEntry(
          id: 1,
          card: _card(1, 'Caterpie'),
          quantity: 1,
          unitPrice: 1000,
          createdAt: DateTime(2026, 9, 13),
          customData: const {'box': 'Kotak A'},
        ),
      ],
      columns: [
        column('date'),
        column('image'),
        column('name'),
        column('expansion'),
        column('number'),
        column('rarity', visible: false),
        column('series', visible: false),
        column('box', custom: true, label: 'Lokasi'),
        column('grade', custom: true, visible: false, label: 'Grade'),
      ],
    );

    expect(find.text('Kelangkaan'), findsNothing);
    expect(find.text('Seri'), findsNothing);
    expect(find.text('Lokasi'), findsOneWidget);
    expect(find.text('Kotak A'), findsOneWidget);
    expect(find.text('Grade'), findsNothing);
    // Always there, whatever the settings say.
    expect(find.text('Jumlah'), findsOneWidget);
    expect(find.text('Catatan'), findsOneWidget);
  });
}
