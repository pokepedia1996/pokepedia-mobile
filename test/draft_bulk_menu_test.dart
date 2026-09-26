import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/draft_bulk_menu.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The menu beside the draft search speaks for every draft at once, so what
/// it reports and what it writes both have to be about the whole pile.
class _FakeRepo extends SellerListingsRepository {
  _FakeRepo._(this.client) : super(client);

  // `autoRefreshToken: false` — a default client starts GoTrue's timer and
  // `testWidgets` fails on one still pending when the tree goes away.
  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  final SupabaseClient client;
  final calls = <Map<String, Object?>>[];

  @override
  Future<String?> updateAllDrafts({bool? autoRelist, bool? acceptsOffers}) async {
    calls.add({'autoRelist': autoRelist, 'acceptsOffers': acceptsOffers});
    return null;
  }
}

SellerDraft _draft(
  int id, {
  int? price,
  bool autoRelist = false,
  bool acceptsOffers = false,
}) => SellerDraft(
  id: id,
  card: CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: 'Charmeleon $id',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '169/165',
    rarity: 'AR',
  ),
  condition: CardCondition.nm,
  quantity: 1,
  photoCount: 0,
  price: price,
  autoRelist: autoRelist,
  acceptsOffers: acceptsOffers,
);

Future<_FakeRepo> _open(
  WidgetTester tester,
  List<SellerDraft> drafts,
) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sellerListingsRepositoryProvider.overrideWithValue(repo),
        sellerDraftsProvider.overrideWith((ref) async => drafts),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: DraftBulkMenu(onChanged: () {})),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Tindakan massal listing'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  return repo;
}

void main() {
  group('draft filter', () {
    test('splits on the one thing a draft can be missing', () {
      final unpriced = _draft(1);
      final priced = _draft(2, price: 45000);

      expect(unpriced.isReady, isFalse);
      expect(priced.isReady, isTrue);

      expect(DraftFilter.all.matches(unpriced), isTrue);
      expect(DraftFilter.needsWork.matches(unpriced), isTrue);
      expect(DraftFilter.needsWork.matches(priced), isFalse);
      expect(DraftFilter.ready.matches(priced), isTrue);
    });

    test('a zero price is not a price', () {
      expect(_draft(1, price: 0).isReady, isFalse);
    });
  });

  group('the bulk menu', () {
    testWidgets('counts every draft, not the ones on screen', (tester) async {
      await _open(tester, [
        _draft(1),
        _draft(2, price: 1),
        _draft(3, price: 2),
      ]);

      expect(find.text('Pilih semua listing'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('TERAPKAN KE SEMUA LISTING'), findsOneWidget);
    });

    testWidgets('a switch is on only when it is true of every draft', (
      tester,
    ) async {
      await _open(tester, [
        _draft(1, autoRelist: true),
        _draft(2, autoRelist: false),
      ]);

      // Mixed reads as off, so one tap makes it true of all of them rather
      // than turning it off for the one draft that had it.
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.first.value, isFalse);
    });

    testWidgets('toggling writes once for the whole pile', (tester) async {
      final repo = await _open(tester, [_draft(1), _draft(2)]);

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['autoRelist'], isTrue);
      // The other switch is left alone — only what was touched is sent.
      expect(repo.calls.single['acceptsOffers'], isNull);
    });
  });
}
