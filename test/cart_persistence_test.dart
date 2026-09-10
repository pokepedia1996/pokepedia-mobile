import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// The cart lives in `cart_items`, but `supabase_flutter` restores a
/// persisted session asynchronously — so the read has to be keyed to the
/// user arriving, not fired once at launch.
const _user = AppUser(id: 'user-1', email: 'ash@pokepedia.id');

CartItem _item(int id) {
  return CartItem(
    cartItemId: id,
    quantity: 1,
    listing: ListingModel(
      id: id,
      sellerId: 'seller-1',
      slug: 'listing-$id',
      side: ListingSide.ask,
      price: 50000,
      condition: CardCondition.nm,
      quantity: 3,
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
  _FakeAuth({AppUser? user}) : _user = user;

  AppUser? _user;

  @override
  Future<AppUser?> build() async => _user;

  /// Named apart from `AuthNotifier.signIn`/`signOut`, which have their own
  /// signatures — these just drive the fake's state.
  void emitUser(AppUser user) {
    _user = user;
    state = AsyncData(user);
  }

  void emitSignedOut() {
    _user = null;
    state = const AsyncData(null);
  }
}

class _FakeCartRepository implements CartRepository {
  _FakeCartRepository(this.rows);

  List<CartItem> rows;
  int fetchCalls = 0;

  @override
  Future<List<CartItem>> fetchCart() async {
    fetchCalls++;
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakeCartRepository repository;

  /// `AuthNotifier.build` is async and the cart's refresh runs in a
  /// microtask, so a couple of turns of the loop are needed before either
  /// has landed.
  Future<void> settle(ProviderContainer container) async {
    await container.pump();
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
      await container.pump();
    }
  }

  ProviderContainer containerWith(_FakeAuth auth) {
    repository = _FakeCartRepository([_item(1), _item(2)]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => auth),
        cartRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // `read` alone doesn't subscribe, so the provider would never be
    // rebuilt when auth changes — which is the whole behaviour under test.
    container.listen(cartProvider, (_, __) {}, fireImmediately: true);
    return container;
  }

  test('a session that arrives after startup still loads the cart', () async {
    // Cold start: the SDK hasn't restored the session yet.
    final auth = _FakeAuth();
    final container = containerWith(auth);

    expect(container.read(cartProvider), isEmpty);
    await settle(container);
    expect(
      repository.fetchCalls,
      0,
      reason:
          'nothing to read without a user, and reading anyway is what '
          'produced an empty cart that never refilled',
    );

    // Session restored a moment later.
    auth.emitUser(_user);
    await settle(container);

    expect(container.read(cartProvider), hasLength(2));
    expect(repository.fetchCalls, 1);
  });

  test('signing out empties the cart', () async {
    final auth = _FakeAuth(user: _user);
    final container = containerWith(auth);

    container.read(cartProvider);
    await settle(container);
    expect(container.read(cartProvider), hasLength(2));

    auth.emitSignedOut();
    await settle(container);

    expect(
      container.read(cartProvider),
      isEmpty,
      reason: "the previous account's items must not stay on screen",
    );
  });

  test(
    'adding while signed out fails fast instead of hitting the RPC',
    () async {
      final auth = _FakeAuth();
      final container = containerWith(auth);

      await expectLater(
        container.read(cartProvider.notifier).add(1, 1),
        throwsA(isA<CartException>()),
      );
      // The fake would throw UnimplementedError if `add` had been forwarded.
      expect(repository.fetchCalls, 0);
    },
  );
}
