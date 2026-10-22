import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/portfolio_page.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/collection_page.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/portfolio_export_row.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_export.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';
import 'package:pokepedia_mobile/shared/utils/csv_export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The portfolio export: every portfolio in one CSV, a Portofolio column
/// saying which shelf each card is on.
PortfolioExportRow _row(
  String portfolio,
  int index, {
  required String name,
  String expansion = 'SV9S',
  String number = '001/099',
  int quantity = 1,
  int? price = 1000,
  String? variantKey,
  String? series,
  String? notes,
  CardLanguage language = CardLanguage.id,
}) => PortfolioExportRow(
  portfolio: portfolio,
  portfolioIndex: index,
  card: CardModel(
    id: name.hashCode,
    category: CardCategory.pokemon,
    nameId: name,
    expansionCode: expansion,
    packSlug: expansion.toLowerCase(),
    collectorNumber: number,
    rarity: 'AR',
    marketPrice: price,
    language: language,
  ),
  quantity: quantity,
  variantKey: variantKey,
  series: series,
  notes: notes,
);

List<String> _lines(String csv) => csv.substring(1).split('\r\n');

const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

late final SupabaseClient _client;

/// An empty collection on screen, and [export] for the export to read.
class _FakeRepository extends PortfolioRepository {
  _FakeRepository(this.export) : super(_client);

  final Future<List<PortfolioExportRow>> Function() export;

  @override
  Future<List<PortfolioExportRow>> fetchPortfolioExport(String userId) =>
      export();

  @override
  Future<CollectionCardsPage> fetchCollectionPage({
    required String? collectionId,
    required CardSortOption sort,
    required CardFilters filters,
    CollectionFacets facets = const CollectionFacets(),
    CollectionCardRow? after,
    int offset = 0,
    int limit = collectionPageSize,
  }) async => const CollectionCardsPage(rows: [], total: 0);

  @override
  Future<CollectionSummary> fetchCollectionSummary(
    String? collectionId,
  ) async => CollectionSummary(
    totalValue: 0,
    uniqueCount: 0,
    totalCount: 0,
    valueNow: 0,
    value7dAgo: 0,
  );

  @override
  Future<CollectionFacets> fetchCollectionFacets(String? collectionId) async =>
      const CollectionFacets();
}

Future<List<({String name, String csv})>> _open(
  WidgetTester tester,
  Future<List<PortfolioExportRow>> Function() export,
) async {
  tester.view.physicalSize = const Size(500 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final shared = <({String name, String csv})>[];
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      listsProvider.overrideWith((ref) async => const []),
      portfolioRepositoryProvider.overrideWithValue(_FakeRepository(export)),
      portfolioValueSeriesProvider.overrideWith((ref) async => const []),
      csvSharerProvider.overrideWithValue(
        (name, csv, origin) async => shared.add((name: name, csv: csv)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const PortfolioPage()),
    ),
  );
  // The loaders animate forever, so a few frames rather than settling.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return shared;
}

Future<void> _tapExport(WidgetTester tester) async {
  await tester.tap(find.text('Ekspor'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('portfolioCsv', () {
    test('a Portofolio column, each portfolio together, in app order', () {
      final lines = _lines(
        portfolioCsv([
          _row('Binder Merah', 1, name: 'Metapod'),
          _row('Utama', 0, name: 'Caterpie'),
          _row('Dagangan', 2, name: 'Weedle'),
          _row('Utama', 0, name: 'Butterfree'),
        ]),
      );

      expect(
        lines[0],
        'Portofolio,Nama Kartu,Varian,Bahasa,Ekspansi,Nomor,Kelangkaan,Seri,'
        'Jumlah,Harga Pasar,Nilai Total,Catatan',
      );
      expect(
        [for (final l in lines.skip(1).take(4)) l.split(',').first],
        ['Utama', 'Utama', 'Binder Merah', 'Dagangan'],
      );
    });

    test('within one, by expansion then number', () {
      final lines = _lines(
        portfolioCsv([
          _row('Utama', 0, name: 'C', expansion: 'SV9S', number: '010/099'),
          _row('Utama', 0, name: 'B', expansion: 'SV9S', number: '002/099'),
          _row('Utama', 0, name: 'A', expansion: 'SV10', number: '050/099'),
        ]),
      );
      expect(
        [for (final l in lines.skip(1).take(3)) l.split(',')[1]],
        ['A', 'B', 'C'],
      );
    });

    test('the card, its count, and what it is worth', () {
      final lines = _lines(
        portfolioCsv([
          _row(
            'Utama',
            0,
            name: 'Caterpie',
            number: '025/165-2',
            quantity: 3,
            price: 2500,
            variantKey: 'reverse',
            series: 'Scarlet & Violet',
            notes: 'Binder hijau',
            language: CardLanguage.jp,
          ),
        ]),
      );
      expect(
        lines[1],
        'Utama,Caterpie,Holo Reverse,JP,SV9S,025/165,AR,Scarlet & Violet,'
        '3,2500,7500,Binder hijau',
      );
    });

    test('no market price is left blank, not zero', () {
      final lines = _lines(
        portfolioCsv([_row('Utama', 0, name: 'Caterpie', price: null)]),
      );
      expect(lines[1], endsWith(',1,,,'));
    });

    test('a list named like a formula stays text', () {
      final csv = portfolioCsv([_row('=SUM(A1)', 1, name: 'Caterpie')]);
      expect(csv, contains("'=SUM(A1)"));
    });

    test('the file is named for the day', () {
      expect(
        portfolioExportFileName(now: DateTime(2026, 10, 21)),
        'pokepedia-portofolio-2026-10-21.csv',
      );
    });
  });

  group('the Ekspor button', () {
    setUpAll(() => _client = SupabaseClient('http://localhost:1', 'anon'));
    tearDownAll(() => _client.dispose());

    testWidgets('shares every portfolio as one CSV', (tester) async {
      final shared = await _open(
        tester,
        () async => [
          _row('Utama', 0, name: 'Caterpie'),
          _row('Binder Merah', 1, name: 'Metapod'),
        ],
      );
      // There even with the portfolio on screen empty: the others may not be.
      expect(find.text('Kelola'), findsNothing);
      await _tapExport(tester);

      expect(shared.single.name, startsWith('pokepedia-portofolio-'));
      expect(shared.single.csv, contains('Utama,Caterpie'));
      expect(shared.single.csv, contains('Binder Merah,Metapod'));
    });

    testWidgets('says so when there is nothing to export', (tester) async {
      final shared = await _open(tester, () async => const []);
      await _tapExport(tester);

      expect(shared, isEmpty);
      expect(find.text('Portofolio masih kosong.'), findsOneWidget);
    });

    testWidgets('says so when the fetch fails', (tester) async {
      final shared = await _open(tester, () async => throw Exception('net'));
      await _tapExport(tester);

      expect(shared, isEmpty);
      expect(find.text('Gagal mengekspor portofolio.'), findsOneWidget);
    });
  });
}
