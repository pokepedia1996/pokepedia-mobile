import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/providers/card_ownership_controller.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/inventory_tab.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// A sync of a large collection stages thousands of drafts. The tables draw
/// them a page at a time, and "Simpan Semua" saves them in a few bulk calls
/// rather than one round trip — and a full re-read — per draft.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _Drafts extends InventoryDraftsNotifier {
  _Drafts(this.drafts);

  final List<InventoryEntry> drafts;

  @override
  Future<List<InventoryEntry>> build() async => drafts;
}

CardModel _card(int id) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Kartu $id',
  expansionCode: 'sv9s',
  packSlug: 'sv9s',
  collectorNumber: '$id/999',
  rarity: 'AR',
);

InventoryEntry _entry(
  int id, {
  int? cardId,
  int quantity = 1,
  String? source,
}) => InventoryEntry(
  id: id,
  card: _card(cardId ?? id),
  quantity: quantity,
  unitPrice: 1000,
  createdAt: DateTime(2026, 9, 1).add(Duration(minutes: id)),
  source: source,
);

/// Confirms every id it is handed, and remembers each bulk call.
class _FakePortfolio implements PortfolioRepository {
  final confirmCalls = <List<int>>[];

  @override
  Future<({Set<int> confirmed, String? error})> confirmDraftRecords({
    required String userId,
    required List<int> recordIds,
    void Function(int done)? onProgress,
  }) async {
    confirmCalls.add(recordIds);
    onProgress?.call(recordIds.length);
    return (confirmed: recordIds.toSet(), error: null);
  }

  @override
  Future<List<InventoryEntry>> fetchDraftRecords(String userId) async => [];

  @override
  Future<List<InventoryEntry>> fetchInventoryRecords(String userId) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

/// Records what is added to the primary collection, per card.
class _FakeExpansions implements ExpansionsRepository {
  final upserts = <int, int>{};

  @override
  Future<String?> upsertUserCard({
    required String userId,
    required int cardId,
    required int delta,
  }) async {
    upserts.update(cardId, (q) => q + delta, ifAbsent: () => delta);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Future<void> _open(
  WidgetTester tester,
  String tab, {
  List<InventoryEntry> records = const [],
  List<InventoryEntry> drafts = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        inventoryRecordsProvider.overrideWith((ref) async => records),
        inventoryDraftsProvider.overrideWith(() => _Drafts(drafts)),
        inventoryActivityProvider.overrideWith((ref) async => []),
        inventoryColumnsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: InventoryTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (tab != 'Database') {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }
}

/// The pager sits under the table, below the fold; the page's list builds
/// it only once it is scrolled to.
Future<void> _scrollToPager(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byTooltip('Halaman berikutnya'),
    find.byType(ListView).first,
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
}

Future<void> _nextPage(WidgetTester tester) async {
  await _scrollToPager(tester);
  await tester.tap(find.byTooltip('Halaman berikutnya'));
  await tester.pumpAndSettle();
}

void main() {
  group('drafts, a page at a time', () {
    final drafts = [for (var i = 1; i <= 45; i++) _entry(i)];

    testWidgets('twenty rows, not forty-five', (tester) async {
      await _open(tester, 'Tambahkan', drafts: drafts);

      expect(find.text('Kartu 1'), findsOneWidget);
      expect(find.text('Kartu 20'), findsOneWidget);
      expect(find.text('Kartu 21'), findsNothing);
      expect(find.text('1–20 dari 45'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('the next page is the next twenty', (tester) async {
      await _open(tester, 'Tambahkan', drafts: drafts);
      await _nextPage(tester);

      expect(find.text('Kartu 20'), findsNothing);
      expect(find.text('Kartu 21'), findsOneWidget);
      expect(find.text('Kartu 40'), findsOneWidget);
      expect(find.text('21–40 dari 45'), findsOneWidget);
    });

    testWidgets('one page needs no pager', (tester) async {
      await _open(tester, 'Tambahkan', drafts: drafts.take(5).toList());
      expect(find.byTooltip('Halaman berikutnya'), findsNothing);
    });
  });

  testWidgets('the database table pages too', (tester) async {
    final records = [for (var i = 1; i <= 25; i++) _entry(i)];
    await _open(tester, 'Database', records: records);

    // Newest first: 25 down to 6, then the last five.
    expect(find.text('Kartu 25'), findsOneWidget);
    expect(find.text('Kartu 6'), findsOneWidget);
    expect(find.text('Kartu 5'), findsNothing);
    await _scrollToPager(tester);
    expect(find.text('1–20 dari 25'), findsOneWidget);

    await _nextPage(tester);
    expect(find.text('Kartu 5'), findsOneWidget);
    expect(find.text('Kartu 25'), findsNothing);
    expect(find.text('21–25 dari 25'), findsOneWidget);
  });

  group('saving every draft', () {
    late _FakePortfolio portfolio;
    late _FakeExpansions expansions;
    late ProviderContainer container;

    setUp(() {
      portfolio = _FakePortfolio();
      expansions = _FakeExpansions();
      container = ProviderContainer(
        overrides: [
          portfolioRepositoryProvider.overrideWithValue(portfolio),
          expansionsRepositoryProvider.overrideWithValue(expansions),
          authProvider.overrideWith(_FakeAuth.new),
        ],
      );
      addTearDown(container.dispose);
    });

    test('is one bulk confirm, not a call per draft', () async {
      final drafts = [for (var i = 1; i <= 1200; i++) _entry(i)];

      final result = await container
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDrafts(userId: 'me', drafts: drafts);

      expect(portfolio.confirmCalls, hasLength(1));
      expect(portfolio.confirmCalls.single, hasLength(1200));
      expect(result.saved, 1200);
      expect(result.failed, 0);
    });

    test('adds hand-typed drafts to the collection, once per card', () async {
      await container
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDrafts(
            userId: 'me',
            drafts: [
              _entry(1, cardId: 10, quantity: 2),
              _entry(2, cardId: 10, quantity: 3),
              _entry(3, cardId: 11, quantity: 1),
            ],
          );

      expect(expansions.upserts, {10: 5, 11: 1});
    });

    test('never adds a synced draft back into the collection', () async {
      // It was copied out of the collection; adding it again would count
      // those cards twice.
      await container
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDrafts(
            userId: 'me',
            drafts: [
              _entry(1, cardId: 10, quantity: 4, source: 'sync'),
              _entry(2, cardId: 11, quantity: 1),
            ],
          );

      expect(expansions.upserts, {11: 1});
    });

    test('a single synced draft is not added either', () async {
      // `confirmInventoryDraft` goes through `confirmDraftRecord`, which
      // the fake doesn't answer — so give it one that does.
      final single = _SingleConfirm();
      final c = ProviderContainer(
        overrides: [
          portfolioRepositoryProvider.overrideWithValue(single),
          expansionsRepositoryProvider.overrideWithValue(expansions),
          authProvider.overrideWith(_FakeAuth.new),
        ],
      );
      addTearDown(c.dispose);

      await c
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDraft(
            userId: 'me',
            recordId: 1,
            cardId: 10,
            quantity: 4,
            unitPrice: 0,
            synced: true,
          );
      expect(expansions.upserts, isEmpty);

      await c
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDraft(
            userId: 'me',
            recordId: 2,
            cardId: 11,
            quantity: 1,
            unitPrice: 0,
          );
      expect(expansions.upserts, {11: 1});
    });
  });
}

class _SingleConfirm extends _FakePortfolio {
  @override
  Future<String?> confirmDraftRecord({
    required String userId,
    required int recordId,
    required int quantity,
    required int unitPrice,
  }) async => null;
}
