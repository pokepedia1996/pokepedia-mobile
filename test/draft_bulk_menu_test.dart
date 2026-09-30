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

/// The menu beside the draft search speaks for the drafts that are ticked,
/// so what it reports and what it writes both have to be about that set —
/// and "Pilih semua listing" has to be what puts drafts in it.
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
  Future<String?> updateDrafts({
    required List<int> ids,
    bool? autoRelist,
    bool? acceptsOffers,
  }) async {
    calls.add({
      'ids': [...ids]..sort(),
      'autoRelist': autoRelist,
      'acceptsOffers': acceptsOffers,
    });
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

late ProviderContainer _container;

Future<_FakeRepo> _open(
  WidgetTester tester,
  List<SellerDraft> drafts, {
  Set<int> selected = const {},
}) async {
  final repo = _FakeRepo();
  _container = ProviderContainer(
    overrides: [
      sellerListingsRepositoryProvider.overrideWithValue(repo),
      sellerDraftsProvider.overrideWith((ref) async => drafts),
    ],
  );
  addTearDown(_container.dispose);
  _container.read(draftSelectionProvider.notifier).state = selected;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
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
    testWidgets('counts what is on screen and says whose switches these are', (
      tester,
    ) async {
      await _open(tester, [
        _draft(1),
        _draft(2, price: 1),
        _draft(3, price: 2),
      ]);

      expect(find.text('Pilih semua listing'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('TERAPKAN KE LISTING TERPILIH'), findsOneWidget);
    });

    testWidgets('the switches are dead until something is ticked', (
      tester,
    ) async {
      await _open(tester, [_draft(1), _draft(2)]);

      // Nothing selected is nothing to apply to, so the rows say so rather
      // than silently writing to the whole table.
      for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
        expect(s.onChanged, isNull);
      }
    });

    testWidgets('"Pilih semua listing" ticks every draft, then clears them', (
      tester,
    ) async {
      await _open(tester, [_draft(1), _draft(2), _draft(3)]);

      await tester.tap(find.text('Pilih semua listing'));
      await tester.pump();
      expect(_container.read(draftSelectionProvider), {1, 2, 3});

      await tester.tap(find.text('Pilih semua listing'));
      await tester.pump();
      expect(_container.read(draftSelectionProvider), isEmpty);
    });

    testWidgets('a switch is on only when it is true of every ticked draft', (
      tester,
    ) async {
      await _open(
        tester,
        [_draft(1, autoRelist: true), _draft(2, autoRelist: false)],
        selected: {1, 2},
      );

      // Mixed reads as off, so one tap makes it true of all of them rather
      // than turning it off for the one draft that had it.
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.first.value, isFalse);
    });

    testWidgets('a switch reads only the ticked drafts', (tester) async {
      await _open(
        tester,
        [_draft(1, autoRelist: true), _draft(2, autoRelist: false)],
        selected: {1},
      );

      // The unticked draft has it off, but it is not part of what this row
      // is about.
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.first.value, isTrue);
    });

    testWidgets('toggling writes once, for the ticked drafts only', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        [_draft(1), _draft(2), _draft(3)],
        selected: {1, 3},
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['ids'], [1, 3]);
      expect(repo.calls.single['autoRelist'], isTrue);
      // The other switch is left alone — only what was touched is sent.
      expect(repo.calls.single['acceptsOffers'], isNull);
    });
  });
}
