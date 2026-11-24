import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/features/market/repository/models/custom_listing_detail.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

StoreModel _store({String? userId = 'seller'}) => StoreModel(
  handle: 'toko-user1',
  storeName: 'Toko User1',
  tagline: '',
  activeListingCount: 1,
  cityName: 'Jakarta',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 0,
  followersCount: 0,
  userId: userId,
  memberSince: DateTime(2026, 7, 1),
);

Map<String, dynamic> _rpcRow() => {
  'id': 7,
  'slug': 'custom-slug',
  'user_id': 'seller',
  'title': 'Paket Charizard & Pikachu',
  'description': 'Isi paket',
  'price': 2900000,
  'quantity': 3,
  'qty_locked': 1,
  'photo_urls': ['https://auth.pokepedia.id/storage/v1/object/public/a.webp'],
  'status': 'open',
  'accepts_offers': true,
  'is_live': true,
  'created_at': '2026-11-23T00:00:00Z',
  'tags': [
    {
      'card_id': 42,
      'condition': 'LP',
      'quantity': 2,
      'card_name': 'Charizard ex',
      'expansion_code': 'SV3',
      'collector_number': '125/197',
      'language': 'jp',
    },
  ],
};

class _Repo implements MarketRepository {
  _Repo(this.row);

  final Object? row;

  @override
  Future<CustomListingDetail?> fetchCustomListing(String slug) async =>
      row is Map<String, dynamic>
      ? CustomListingDetail.fromJson(row as Map<String, dynamic>)
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _NoAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Future<CustomListingData?> _read({
  required Object? row,
  required StoreModel? store,
}) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_NoAuth.new),
      marketRepositoryProvider.overrideWithValue(_Repo(row)),
      storeDetailProvider('toko-user1').overrideWith((ref) async => store),
    ],
  );
  addTearDown(container.dispose);
  // Signed in or out settles first: the provider re-reads when it changes.
  await container.read(authProvider.future);
  return container.read(
    customListingProvider((
      storeSlug: 'toko-user1',
      slug: 'custom-slug',
    )).future,
  );
}

void main() {
  test('joins the listing to the store that sells it', () async {
    final data = await _read(row: _rpcRow(), store: _store());

    expect(data, isNotNull);
    expect(data!.detail.title, 'Paket Charizard & Pikachu');
    expect(data.detail.available, 2);
    expect(data.detail.tags.single.name, 'Charizard ex');
    expect(data.detail.tags.single.packSlug, 'sv3');
    expect(data.listing.isCustom, isTrue);
    expect(data.listing.storeSlug, 'toko-user1');
    expect(data.listing.sellerId, 'seller');
    expect(data.listing.photoUrls, hasLength(1));
  });

  test('a link naming someone else\'s store is not found', () async {
    final data = await _read(
      row: _rpcRow(),
      store: _store(userId: 'other'),
    );

    expect(data, isNull);
  });

  test('a store that does not exist is not found', () async {
    expect(await _read(row: _rpcRow(), store: null), isNull);
  });

  test('a listing the RPC will not show is not found', () async {
    expect(await _read(row: null, store: _store()), isNull);
  });

  test('a draft has no price and none is invented beyond 0', () {
    final detail = CustomListingDetail.fromJson({
      ..._rpcRow(),
      'price': null,
      'status': 'draft',
      'is_live': false,
    });

    expect(detail.price, 0);
    expect(detail.isLive, isFalse);
  });

  test('a photo entry that is not a string is skipped, not thrown on', () {
    final detail = CustomListingDetail.fromJson({
      ..._rpcRow(),
      'photo_urls': [
        7,
        'https://auth.pokepedia.id/storage/v1/object/public/a.webp',
      ],
    });

    expect(detail.photoUrls, hasLength(1));
  });

  test('a tag with no catalog page opens nothing', () {
    final tag = CustomTaggedCard.fromJson({'card_id': null, 'card_name': 'X'});

    expect(tag.packSlug, isNull);
  });
}
