import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/inventory_tab.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/wantlist_model.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';

/// Before anything is typed, the add tab offers web's "Sinkronkan Koleksi"
/// and says how searching works; once a search starts, both make way for
/// the results.
const _me = AppUser(id: 'me', email: 'me@example.com');

const _hint =
    'Ketik nama, nomor, ekspansi, atau kelangkaan kartu di atas untuk mencari.';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

/// Records each sync and answers with [inserted].
class _FakeRepo implements PortfolioRepository {
  _FakeRepo({this.inserted = 0});

  final int inserted;
  final synced = <({String userId, String? collectionId})>[];

  @override
  Future<({int inserted, String? error})> syncInventoryFromCollection({
    required String userId,
    String? collectionId,
  }) async {
    synced.add((userId: userId, collectionId: collectionId));
    return (inserted: inserted, error: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Future<void> _open(WidgetTester tester, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioRepositoryProvider.overrideWithValue(repo),
        inventoryRecordsProvider.overrideWith((ref) async => []),
        inventoryDraftsProvider.overrideWith(() => _Drafts(const [])),
        inventoryColumnsProvider.overrideWith((ref) async => const []),
        listsProvider.overrideWith(
          (ref) async => [
            WantlistModel(
              id: 'list-1',
              name: 'Binder Merah',
              slug: 'binder-merah',
              cardCount: 12,
              createdAt: DateTime(2026, 9, 1),
              updatedAt: DateTime(2026, 9, 1),
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: InventoryTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tambahkan'));
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
  testWidgets('with nothing typed: the sync button and the hint', (
    tester,
  ) async {
    await _open(tester, _FakeRepo());

    expect(find.text('Sinkronkan Koleksi'), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('they go the moment typing starts, and come back on clear', (
    tester,
  ) async {
    await _open(tester, _FakeRepo());

    // One pump, inside the search debounce: gone already, not 400ms later.
    await tester.enterText(find.byType(TextField).first, 'p');
    await tester.pump();
    expect(find.text('Sinkronkan Koleksi'), findsNothing);
    expect(find.text(_hint), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(find.text('Sinkronkan Koleksi'), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('syncs the main collection by default', (tester) async {
    final repo = _FakeRepo(inserted: 3);
    await _open(tester, repo);

    await tester.tap(find.text('Sinkronkan Koleksi'));
    await tester.pumpAndSettle();
    expect(find.text('Sinkronkan dari koleksi'), findsOneWidget);
    expect(find.text('Binder Merah'), findsOneWidget);
    expect(find.text('12 kartu'), findsOneWidget);

    await tester.tap(find.text('Sinkronkan'));
    await tester.pumpAndSettle();

    // Null asks the function for the user's main collection.
    expect(repo.synced.single.collectionId, isNull);
    expect(repo.synced.single.userId, 'me');
    expect(find.text('3 draft ditambahkan dari "Utama".'), findsOneWidget);
  });

  testWidgets('or the list picked, and says when nothing was missing', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await _open(tester, repo);

    await tester.tap(find.text('Sinkronkan Koleksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Binder Merah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinkronkan'));
    await tester.pumpAndSettle();

    expect(repo.synced.single.collectionId, 'list-1');
    expect(
      find.text('"Binder Merah" sudah sinkron dengan inventori.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling syncs nothing', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo);

    await tester.tap(find.text('Sinkronkan Koleksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(repo.synced, isEmpty);
  });
}
