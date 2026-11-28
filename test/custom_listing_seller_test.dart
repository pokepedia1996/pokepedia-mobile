import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/card_custom_listings_section.dart';
import 'package:pokepedia_mobile/features/market/repository/models/card_custom_listing.dart';
import 'package:pokepedia_mobile/features/seller/presentation/custom_listing_form_page.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/custom_listing_widgets.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/listing_card_tile.dart';
import 'package:pokepedia_mobile/features/seller/repository/custom_listings_repository.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/custom_listing_form.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Custom listings on the seller's side: the form's rules, the form itself,
/// how they show in Kelola Listing, and the card page's "Listing custom".

const _photo =
    'https://tlauakxyrxpwnwgdywum.supabase.co/storage/v1/object/public/'
    'listing-photos/u1/a.jpg';

CustomFormTag _tag({
  int cardId = 1,
  CardCondition condition = CardCondition.nm,
  int quantity = 1,
}) => CustomFormTag(
  cardId: cardId,
  name: 'Pikachu',
  number: '025/165',
  expansionCode: 'sv2a',
  language: CardLanguage.id,
  condition: condition,
  quantity: quantity,
);

class _FakeCustomRepo implements CustomListingsRepository {
  _FakeCustomRepo({this.existing});

  final CustomListingFormValue? existing;
  final saves = <({CustomListingFormValue value, bool publish})>[];

  @override
  Future<CustomListingFormValue?> fetchForEdit(String slug) async => existing;

  @override
  Future<CustomListingSaveResult> save(
    CustomListingFormValue value, {
    required bool publish,
  }) async {
    saves.add((value: value, publish: publish));
    return (slug: value.slug ?? 'new-slug', published: publish, error: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSellerRepo implements SellerListingsRepository {
  @override
  Future<ListingDefaults> fetchListingDefaults() async =>
      const ListingDefaults(acceptsOffers: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The form on a route of its own, so a publish can pop back to "/".
Future<({_FakeCustomRepo repo, List<bool?> popped})> _pumpForm(
  WidgetTester tester, {
  String? slug,
  CustomListingFormValue? existing,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repo = _FakeCustomRepo(existing: existing);
  final popped = <bool?>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                popped.add(await context.push<bool>('/form')),
            child: const Text('open'),
          ),
        ),
      ),
      GoRoute(
        path: '/form',
        builder: (_, __) => CustomListingFormPage(slug: slug),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        customListingsRepositoryProvider.overrideWithValue(repo),
        sellerListingsRepositoryProvider.overrideWithValue(_FakeSellerRepo()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (repo: repo, popped: popped);
}

void main() {
  group('form rules', () {
    test('a title is 5 to 40 characters, trimmed', () {
      expect(customTitleError('Abc '), 'Judul minimal 5 karakter.');
      expect(customTitleError('Paket A'), isNull);
      expect(customTitleError('x' * 41), 'Judul maksimal 40 karakter.');
    });

    test('the same card in the same condition is one tag, up to 99', () {
      final merged = mergeCustomTags(
        [_tag(quantity: 98)],
        [_tag(quantity: 5), _tag(condition: CardCondition.lp)],
      );
      expect(merged, hasLength(2));
      expect(merged.first.quantity, 99);
      expect(merged.last.condition, CardCondition.lp);
    });

    test('publishing needs a photo, then a title, then a price', () {
      const blank = CustomListingFormValue();
      expect(blank.publishBlocker, 'Tambahkan minimal 1 foto.');
      final withPhoto = blank.copyWith(photoUrls: [_photo]);
      expect(withPhoto.publishBlocker, 'Judul minimal 5 karakter.');
      final titled = withPhoto.copyWith(title: 'Paket starter');
      expect(titled.publishBlocker, 'Isi harga dulu.');
      expect(titled.copyWith(price: () => 50000).publishBlocker, isNull);
    });

    test('saves with the RPC parameters web sends', () {
      final value = CustomListingFormValue(
        slug: 's1',
        title: 'Paket starter',
        price: 50000,
        quantity: 2,
        photoUrls: const [_photo],
        tags: [_tag(condition: CardCondition.lp, quantity: 3)],
        acceptsOffers: true,
      );
      expect(value.toRpcParams(publish: true), {
        'p_slug': 's1',
        'p_title': 'Paket starter',
        'p_description': '',
        'p_price': 50000,
        'p_quantity': 2,
        'p_photo_urls': [_photo],
        'p_tags': [
          {'card_id': 1, 'condition': 'LP', 'quantity': 3},
        ],
        'p_accepts_offers': true,
        'p_auto_relist': false,
        'p_publish': true,
      });
    });

    test('an edit keeps the stored photo URLs, which is all the RPC takes', () {
      final value = CustomListingFormValue.fromDetail({
        'slug': 's1',
        'title': 'Paket',
        'price': 1000,
        'quantity': 3,
        'qty_locked': 1,
        'photo_urls': [_photo],
        'status': 'open',
        'accepts_offers': false,
        'auto_relist': true,
        'tags': [
          {
            'card_id': 9,
            'condition': 'MP',
            'quantity': 2,
            'card_name': 'Eevee',
          },
        ],
      });
      expect(value.photoUrls, [_photo]);
      expect(value.isDraft, isFalse);
      expect(value.qtyLocked, 1);
      expect(value.tags.single.condition, CardCondition.mp);
    });

    test("the RPC's refusals in the seller's words", () {
      expect(
        customListingSaveError('no_couriers'),
        'Pilih kurir di pengaturan toko.',
      );
      expect(
        customListingSaveError('something_new'),
        'Gagal menyimpan listing.',
      );
    });
  });

  group('form', () {
    testWidgets('a new listing starts from Preferensi and blocks an empty '
        'publish', (tester) async {
      final form = await _pumpForm(tester);

      expect(find.text('Listing custom'), findsOneWidget);
      expect(find.text('Simpan draft'), findsOneWidget);
      expect(find.text('Pasang listing'), findsOneWidget);

      await tester.tap(find.text('Pasang listing'));
      await tester.pump();
      expect(form.repo.saves, isEmpty);
      expect(find.text('Tambahkan minimal 1 foto.'), findsWidgets);
    });

    testWidgets('a draft saves half-filled and stays open', (tester) async {
      final form = await _pumpForm(tester);

      await tester.enterText(find.byType(TextField).first, 'Paket A');
      await tester.tap(find.text('Simpan draft'));
      await tester.pumpAndSettle();

      final save = form.repo.saves.single;
      expect(save.publish, isFalse);
      expect(save.value.title, 'Paket A');
      // Preferensi said offers on.
      expect(save.value.acceptsOffers, isTrue);
      expect(find.text('Listing custom'), findsOneWidget);
      expect(form.popped, isEmpty);
    });

    testWidgets('a live listing saves its changes and goes back', (
      tester,
    ) async {
      final form = await _pumpForm(
        tester,
        slug: 's1',
        existing: CustomListingFormValue(
          slug: 's1',
          title: 'Paket starter',
          price: 50000,
          photoUrls: const [_photo],
          tags: [_tag()],
          isDraft: false,
        ),
      );

      // Live: no draft to fall back to.
      expect(find.text('Simpan draft'), findsNothing);
      expect(find.text('Pikachu'), findsOneWidget);
      expect(find.text('Rp50.000'), findsOneWidget);

      await tester.tap(find.text('Simpan perubahan'));
      await tester.pumpAndSettle();

      expect(form.repo.saves.single.publish, isTrue);
      expect(form.repo.saves.single.value.slug, 's1');
      expect(form.popped, [true]);
    });

    testWidgets('someone else\'s or a missing listing is not editable', (
      tester,
    ) async {
      await _pumpForm(tester, slug: 'gone');
      expect(find.text('Listing tidak ditemukan'), findsOneWidget);
      expect(find.text('Pasang listing'), findsNothing);
    });
  });

  group('Kelola Listing', () {
    test('a custom row reads as its title, with no grade', () {
      final listing = SellerListing.fromRow({
        'slug': 's1',
        'kind': 'custom',
        'title': 'Binder Pikachu',
        'card_id': null,
        'card_name': null,
        'condition': null,
        'price': 150000,
        'quantity': 1,
        'qty_locked': 0,
        'status': 'open',
        'photo_urls': [_photo],
      });
      expect(listing.isCustom, isTrue);
      expect(listing.card.name, 'Binder Pikachu');
      expect(listing.card.hasCondition, isFalse);
      expect(listing.card.imageUrl, isNotNull);
    });

    testWidgets('a custom row says CUSTOM and opens its form', (tester) async {
      var edits = 0;
      final listing = SellerListing.fromRow({
        'slug': 's1',
        'kind': 'custom',
        'title': 'Binder Pikachu',
        'price': 150000,
        'quantity': 2,
        'qty_locked': 0,
        'status': 'open',
        'photo_urls': [_photo, _photo],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListingCardTile(
              listing: listing,
              offerCount: 0,
              onToggleAutoRelist: (_) {},
              onToggleOffers: (_) {},
              onMenu: () {},
              onEdit: () => edits++,
            ),
          ),
        ),
      );

      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('2 foto'), findsOneWidget);
      expect(find.text('NM'), findsNothing);

      await tester.tap(find.text('Binder Pikachu'));
      expect(edits, 1);
    });

    testWidgets('Tambahkan Listing offers Singles and Custom', (tester) async {
      NewListingKind? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    picked = await showAddListingChooser(context),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();

      expect(find.text('Singles'), findsOneWidget);
      expect(find.text('Kartu dari katalog'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(picked, NewListingKind.custom);
    });
  });

  testWidgets('a card page row: this card in the bundle, and the rest', (
    tester,
  ) async {
    final row = CardCustomListing.fromRow({
      'id': 1,
      'slug': 's1',
      'title': 'Paket Eevee',
      'price': 120000,
      'available': 3,
      'photo_urls': [_photo],
      'tag_condition': 'LP',
      'tag_quantity': 2,
      'tag_count': 3,
      'store_slug': null,
      'store_name': 'Toko Ash',
      'username': 'ash',
      'city_name': 'Kota Bandung',
    });
    expect(row.handle, 'ash');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: CardCustomListingRow(row: row)),
      ),
    );
    expect(find.text('Paket Eevee'), findsOneWidget);
    expect(find.text('Kartu ini LP ×2 · +2 kartu lain'), findsOneWidget);
    expect(find.text('Toko Ash · Kota Bandung'), findsOneWidget);
    expect(find.text('Rp120.000'), findsOneWidget);
    expect(find.text('3 tersedia'), findsOneWidget);
  });
}
