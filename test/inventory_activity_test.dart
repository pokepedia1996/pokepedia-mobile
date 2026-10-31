import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/inventory_tab.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/shared/utils/csv_export.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The Aktivitas tab is web's activity table: searchable, sortable from
/// each header, a page at a time, and following the column settings kept
/// on web.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _Drafts extends InventoryDraftsNotifier {
  @override
  Future<List<InventoryEntry>> build() async => const [];
}

CardModel _card(int id, String name, {String number = '001/099'}) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: name,
  expansionCode: 'sv9s',
  packSlug: 'sv9s',
  collectorNumber: number,
  rarity: 'AR',
);

InventoryActivityEntry _row(
  int id,
  String name, {
  InventoryActivityAction action = InventoryActivityAction.addedIn,
  int quantity = 1,
  int unitPrice = 1000,
  DateTime? at,
  String? series,
  int? seriesId,
  String? variantKey,
  String number = '001/099',
}) => InventoryActivityEntry(
  id: id,
  card: _card(id, name, number: number),
  action: action,
  quantity: quantity,
  unitPrice: unitPrice,
  createdAt: at ?? DateTime(2026, 9, 1).add(Duration(hours: id)),
  series: series,
  seriesId: seriesId,
  variantKey: variantKey,
);

Future<void> _open(
  WidgetTester tester,
  List<InventoryActivityEntry> activity, {
  List<InventoryColumn> columns = const [],
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        inventoryRecordsProvider.overrideWith((ref) async => []),
        inventoryDraftsProvider.overrideWith(_Drafts.new),
        inventoryActivityProvider.overrideWith((ref) async => activity),
        inventoryColumnsProvider.overrideWith((ref) async => columns),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: InventoryTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aktivitas'));
  await tester.pumpAndSettle();
}

Future<void> _tapHeader(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

List<String> _order(WidgetTester tester, List<String> names) {
  final ys = {for (final n in names) n: tester.getTopLeft(find.text(n)).dy};
  return [...names]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

void main() {
  testWidgets('each action in web\'s words', (tester) async {
    await _open(tester, [
      _row(1, 'Caterpie'),
      _row(2, 'Metapod', action: InventoryActivityAction.removedOut),
      _row(3, 'Butterfree', action: InventoryActivityAction.updated),
    ]);

    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
    expect(find.text('Perbaikan'), findsOneWidget);
  });

  testWidgets('the series, the finish and the bare number', (tester) async {
    await _open(tester, [
      _row(
        1,
        'Caterpie',
        series: 'Scarlet & Violet',
        variantKey: 'reverse',
        number: '025/165-2',
      ),
    ]);

    expect(find.text('Scarlet & Violet'), findsOneWidget);
    expect(find.text('Holo Reverse'), findsOneWidget);
    expect(find.text('025/165'), findsOneWidget);
  });

  group('sorting', () {
    final rows = [
      _row(1, 'Caterpie', quantity: 1, unitPrice: 9000, seriesId: 8),
      _row(2, 'Metapod', quantity: 5, unitPrice: 1000, seriesId: 9),
      _row(3, 'Butterfree', quantity: 3, unitPrice: 4000, seriesId: 7),
    ];
    const names = ['Caterpie', 'Metapod', 'Butterfree'];

    testWidgets('latest first until a header is tapped', (tester) async {
      await _open(tester, rows);
      expect(_order(tester, names), ['Butterfree', 'Metapod', 'Caterpie']);
    });

    testWidgets('by name, then reversed', (tester) async {
      await _open(tester, rows);

      await _tapHeader(tester, 'Nama Kartu');
      expect(_order(tester, names), ['Butterfree', 'Caterpie', 'Metapod']);

      await _tapHeader(tester, 'Nama Kartu');
      expect(_order(tester, names), ['Metapod', 'Caterpie', 'Butterfree']);
    });

    testWidgets('by quantity, total and series', (tester) async {
      await _open(tester, rows);

      await _tapHeader(tester, 'Jumlah');
      expect(_order(tester, names), ['Caterpie', 'Butterfree', 'Metapod']);

      // Totals: 9.000, 5.000, 12.000.
      await _tapHeader(tester, 'Harga Total');
      expect(_order(tester, names), ['Metapod', 'Caterpie', 'Butterfree']);

      // Release order: 7, 8, 9.
      await _tapHeader(tester, 'Seri');
      expect(_order(tester, names), ['Butterfree', 'Caterpie', 'Metapod']);
    });
  });

  testWidgets('the search narrows the trail', (tester) async {
    await _open(tester, [
      _row(1, 'Caterpie', unitPrice: 2500),
      _row(2, 'Metapod'),
    ]);

    await tester.enterText(find.byType(TextField), 'metap');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Metapod'), findsOneWidget);
    expect(find.text('Caterpie'), findsNothing);

    // Prices count, as they do on web.
    await tester.enterText(find.byType(TextField), '2.500');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Caterpie'), findsOneWidget);
    expect(find.text('Metapod'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.text('Tidak ada aktivitas yang cocok dengan pencarian.'),
      findsOneWidget,
    );
  });

  testWidgets('twenty rows a page', (tester) async {
    await _open(tester, [for (var i = 1; i <= 25; i++) _row(i, 'Kartu $i')]);

    expect(find.text('Kartu 25'), findsOneWidget);
    expect(find.text('Kartu 6'), findsOneWidget);
    expect(find.text('Kartu 5'), findsNothing);

    await tester.dragUntilVisible(
      find.byTooltip('Halaman berikutnya'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('1–20 dari 25'), findsOneWidget);
    await tester.tap(find.byTooltip('Halaman berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Kartu 5'), findsOneWidget);
    expect(find.text('Kartu 25'), findsNothing);
  });

  testWidgets('the columns hidden on web stay hidden', (tester) async {
    InventoryColumn column(String key, {bool visible = true}) =>
        InventoryColumn(
          key: key,
          label: key,
          isVisible: visible,
          isCustom: false,
          isNumber: false,
        );

    await _open(
      tester,
      [_row(1, 'Caterpie', series: 'Scarlet & Violet')],
      columns: [
        column('date'),
        column('name'),
        column('expansion'),
        column('number'),
        column('rarity', visible: false),
        column('series', visible: false),
      ],
    );

    expect(find.text('Kelangkaan'), findsNothing);
    expect(find.text('Seri'), findsNothing);
    expect(find.text('Scarlet & Violet'), findsNothing);
    // Always there, whatever the settings say.
    for (final header in ['Aksi', 'Jumlah', 'Harga Satuan', 'Harga Total']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
  });

  group('tapping a row opens its card', () {
    Future<void> openRouted(
      WidgetTester tester,
      String tab, {
      List<InventoryEntry> records = const [],
      List<InventoryActivityEntry> activity = const [],
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: InventoryTab()),
          ),
          GoRoute(
            path: '/expansions/:pack/:id',
            builder: (_, state) => Text(
              'card ${state.pathParameters['pack']}/'
              '${state.pathParameters['id']}',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            inventoryRecordsProvider.overrideWith((ref) async => records),
            inventoryDraftsProvider.overrideWith(_Drafts.new),
            inventoryActivityProvider.overrideWith((ref) async => activity),
            inventoryColumnsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    testWidgets('from Aktivitas', (tester) async {
      await openRouted(tester, 'Aktivitas', activity: [_row(7, 'Caterpie')]);

      // Underlined, as a link.
      expect(
        tester.widget<Text>(find.text('Caterpie')).style?.decoration,
        TextDecoration.underline,
      );

      await tester.tap(find.text('Caterpie'));
      await tester.pumpAndSettle();
      expect(find.text('card sv9s/7'), findsOneWidget);
    });

    testWidgets('from Database', (tester) async {
      await openRouted(
        tester,
        'Database',
        records: [
          InventoryEntry(
            id: 1,
            card: _card(9, 'Metapod'),
            quantity: 1,
            unitPrice: 1000,
            createdAt: DateTime(2026, 9, 1),
          ),
        ],
      );

      // Underlined, as a link.
      expect(
        tester.widget<Text>(find.text('Metapod')).style?.decoration,
        TextDecoration.underline,
      );

      await tester.tap(find.text('Metapod'));
      await tester.pumpAndSettle();
      expect(find.text('card sv9s/9'), findsOneWidget);
    });
  });

  group('export', () {
    final today = DateUtils.dateOnly(DateTime.now());
    // Today, three days ago, and two months back.
    final rows = [
      _row(1, 'Caterpie', at: today.add(const Duration(hours: 10))),
      _row(2, 'Metapod', at: today.subtract(const Duration(days: 3))),
      _row(3, 'Butterfree', at: today.subtract(const Duration(days: 60))),
    ];

    late List<({String name, String csv})> shared;
    late Override sharer;

    setUp(() {
      shared = [];
      sharer = csvSharerProvider.overrideWithValue(
        (name, csv, origin) async => shared.add((name: name, csv: csv)),
      );
    });

    Future<void> openSheet(WidgetTester tester) async {
      await _open(tester, rows, overrides: [sharer]);
      await tester.tap(find.byTooltip('Ekspor'));
      await tester.pumpAndSettle();
    }

    testWidgets('everything, by default', (tester) async {
      await openSheet(tester);
      expect(find.text('3 aktivitas akan diekspor.'), findsOneWidget);

      await tester.tap(find.text('Ekspor CSV'));
      await tester.pumpAndSettle();

      expect(shared.single.name, startsWith('pokepedia-aktivitas-semua-'));
      for (final name in ['Caterpie', 'Metapod', 'Butterfree']) {
        expect(shared.single.csv, contains(name));
      }
    });

    testWidgets('only the days picked', (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('7 hari terakhir'));
      await tester.pumpAndSettle();
      expect(find.text('2 aktivitas akan diekspor.'), findsOneWidget);

      await tester.tap(find.text('Ekspor CSV'));
      await tester.pumpAndSettle();

      final csv = shared.single.csv;
      expect(csv, contains('Caterpie'));
      expect(csv, contains('Metapod'));
      expect(csv, isNot(contains('Butterfree')));
    });

    testWidgets('the search on screen doesn\'t narrow it', (tester) async {
      await _open(tester, rows, overrides: [sharer]);
      await tester.enterText(find.byType(TextField), 'metap');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Ekspor'));
      await tester.pumpAndSettle();
      expect(find.text('3 aktivitas akan diekspor.'), findsOneWidget);
    });

    testWidgets('a range with nothing in it exports nothing', (tester) async {
      // Only the row from two months back, and the last week picked.
      await _open(tester, [rows.last], overrides: [sharer]);
      await tester.tap(find.byTooltip('Ekspor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 hari terakhir'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada aktivitas di rentang ini.'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Ekspor CSV'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Pilih tanggal opens a calendar', (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Pilih tanggal'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih rentang tanggal'), findsOneWidget);

      // Closing it without picking leaves the range as it was.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('3 aktivitas akan diekspor.'), findsOneWidget);
    });

    // Each preset's range can start before the oldest activity; the
    // calendar still has to open on it.
    for (final preset in ['7 hari terakhir', '30 hari terakhir', 'Bulan ini']) {
      testWidgets('Pilih tanggal opens after $preset', (tester) async {
        // Nothing older than today.
        await _open(tester, [rows.first], overrides: [sharer]);
        await tester.tap(find.byTooltip('Ekspor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(preset));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Pilih tanggal'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Pilih rentang tanggal'), findsOneWidget);
      });
    }

    testWidgets('Batal shares nothing', (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(shared, isEmpty);
    });
  });
}
