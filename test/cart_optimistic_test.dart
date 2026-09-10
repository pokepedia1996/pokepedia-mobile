import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// The badge has to move on the first frame and settle behind the user —
/// web's `cart-count-context` pending-delta, ported.
const _user = AppUser(id: 'user-1', email: 'ash@pokepedia.id');

CartItem _item(int id, {int listingId = 0}) {
  return CartItem(
    cartItemId: id,
    quantity: 1,
    listing: ListingModel(
      id: listingId == 0 ? id : listingId,
      sellerId: 'seller-1',
      slug: 'listing-$id',
      side: ListingSide.ask,
      price: 50000,
      condition: CardCondition.nm,
      quantity: 5,
      card: const CardModel(
        id: 1,
        category: CardCategory.pokemon,
        nameId: 'Pikachu',
        expansionCode: 'SV2a',
        packSlug: 'sv2a',
        collectorNumber: '025/165',
        rarity: 'Rare',
      ),
      storeSlug: 'toko',
      storeName: 'Toko',
      isVerified: false,
      cityName: 'Jakarta',
      createdAt: DateTime(2026, 8, 1),
    ),
  );
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _user;
}

class _FakeCartRepository implements CartRepository {
  _FakeCartRepository(this.rows);

  List<CartItem> rows;

  /// Held open so the test can observe the window between tapping and the
  /// server answering — the whole point of the optimistic path.
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<List<CartItem>> fetchCart() async => rows;

  @override
  Future<void> add(int listingId, int quantity) async {
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    rows = [...rows, _item(rows.length + 10, listingId: listingId)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakeCartRepository repository;

  Future<ProviderContainer> containerWith(List<CartItem> rows) async {
    repository = _FakeCartRepository(rows);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        cartRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cartCountProvider, (_, __) {}, fireImmediately: true);
    for (var i = 0; i < 4; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }
    return container;
  }

  test('the badge moves before the server answers', () async {
    final container = await containerWith([_item(1)]);
    expect(container.read(cartCountProvider), 1);

    repository.gate = Completer<void>();
    final pending = container.read(cartProvider.notifier).add(99, 1);
    await container.pump();

    expect(
      container.read(cartCountProvider),
      2,
      reason: 'the count must not wait on the round trip',
    );

    repository.gate!.complete();
    await pending;
    for (var i = 0; i < 4; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }

    // Settled on the server's list, with no double-count from the delta.
    expect(container.read(cartCountProvider), 2);
    expect(container.read(cartProvider), hasLength(2));
  });

  test('a rejected add rolls the badge back', () async {
    final container = await containerWith([_item(1)]);

    repository.gate = Completer<void>();
    repository.failWith = const CartException('Stok habis');
    final pending = container.read(cartProvider.notifier).add(99, 1);
    await container.pump();
    expect(container.read(cartCountProvider), 2);

    repository.gate!.complete();
    await expectLater(pending, throwsA(isA<CartException>()));
    await container.pump();

    expect(
      container.read(cartCountProvider),
      1,
      reason: 'the count must never keep a card the server refused',
    );
  });

  test('re-adding a listing already in the cart moves nothing', () async {
    // `add_to_cart` upserts the quantity rather than accumulating, so this
    // is not a new line and the badge would be wrong to increment.
    final container = await containerWith([_item(1, listingId: 55)]);
    expect(container.read(cartCountProvider), 1);

    repository.gate = Completer<void>();
    final pending = container.read(cartProvider.notifier).add(55, 3);
    await container.pump();

    expect(container.read(cartCountProvider), 1);

    repository.gate!.complete();
    await pending;
  });
}
