import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/draft_selection_bar.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends SellerListingsRepository {
  _FakeRepo._(SupabaseClient c) : super(c);

  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  final confirmed = <int>[];

  @override
  Future<String?> confirmDraft(int id) async {
    confirmed.add(id);
    return null;
  }
}

SellerDraft _draft(int id, {int? price}) => SellerDraft(
  id: id,
  card: CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: 'Kartu $id',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '1/165',
    rarity: 'AR',
  ),
  condition: CardCondition.nm,
  quantity: 1,
  photoCount: 0,
  price: price,
);

Future<_FakeRepo> _open(
  WidgetTester tester, {
  required List<SellerDraft> drafts,
  required Set<int> selected,
}) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sellerListingsRepositoryProvider.overrideWithValue(repo),
        sellerDraftsProvider.overrideWith((ref) async => drafts),
        draftSelectionProvider.overrideWith((ref) => selected),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: DraftSelectionBar(onDone: () async {})),
      ),
    ),
  );
  // The drafts provider is async; the bar's counts depend on it.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return repo;
}

void main() {
  testWidgets('stays out of the way until something is ticked', (tester) async {
    await _open(tester, drafts: [_draft(1, price: 5)], selected: const {});
    expect(find.textContaining('dipilih'), findsNothing);
  });

  testWidgets('counts what is ticked, but offers what can be posted', (
    tester,
  ) async {
    await _open(
      tester,
      drafts: [_draft(1, price: 5000), _draft(2), _draft(3)],
      selected: const {1, 2, 3},
    );

    // Three ticked...
    expect(find.text('3 dipilih'), findsOneWidget);
    // ...but only the priced one can actually be posted, and saying
    // "Pasang 3" would be a promise the server refuses twice.
    expect(find.text('Pasang 1 listing'), findsOneWidget);
  });

  testWidgets('posts only the drafts that are ready', (tester) async {
    final repo = await _open(
      tester,
      drafts: [_draft(1, price: 5000), _draft(2), _draft(3, price: 9000)],
      selected: const {1, 2, 3},
    );

    await tester.tap(find.text('Pasang 2 listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.confirmed, [1, 3]);
  });

  testWidgets('the two actions sit at the right, the count at the left', (
    tester,
  ) async {
    await _open(tester, drafts: [_draft(1, price: 5000)], selected: const {1});

    final count = tester.getTopLeft(find.text('1 dipilih')).dx;
    final trash = tester.getTopLeft(find.byIcon(LucideIcons.trash2)).dx;
    final button = tester.getTopLeft(find.byType(FilledButton)).dx;
    final barRight = tester.getTopRight(find.byType(DraftSelectionBar)).dx;

    // Count first, then the two actions, hard against the right edge.
    expect(count, lessThan(trash));
    expect(trash, lessThan(button));
    expect(
      tester.getTopRight(find.byType(FilledButton)).dx,
      greaterThan(barRight - 40),
    );
  });

  testWidgets('nothing postable leaves the button disabled', (tester) async {
    await _open(tester, drafts: [_draft(1), _draft(2)], selected: const {1, 2});

    expect(find.text('Pasang 0 listing'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
