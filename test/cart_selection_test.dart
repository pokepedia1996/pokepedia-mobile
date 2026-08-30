import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// Selection decides what is actually bought — it's posted as
/// `selectedCartItemIds` — so these pin the rules rather than the pixels.
CartItem _item(
  int id, {
  String sellerId = 'seller-1',
  int stock = 3,
  ListingStatus status = ListingStatus.open,
  int price = 50000,
  int quantity = 1,
}) {
  return CartItem(
    cartItemId: id,
    quantity: quantity,
    listing: ListingModel(
      id: id,
      sellerId: sellerId,
      slug: 'listing-$id',
      side: ListingSide.ask,
      price: price,
      condition: CardCondition.nm,
      quantity: stock,
      status: status,
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

/// Stands in for the DB-backed cart.
class _FakeCart extends CartNotifier {
  _FakeCart(this._items);

  List<CartItem> _items;

  @override
  List<CartItem> build() => _items;

  void emit(List<CartItem> items) {
    _items = items;
    state = items;
  }
}

ProviderContainer _containerWith(_FakeCart cart) {
  final container = ProviderContainer(
    overrides: [cartProvider.overrideWith(() => cart)],
  );
  addTearDown(container.dispose);
  container.listen(cartSelectionProvider, (_, __) {}, fireImmediately: true);
  return container;
}

void main() {
  test('everything available starts selected', () {
    final container = _containerWith(_FakeCart([_item(1), _item(2)]));
    expect(container.read(cartSelectionProvider), {1, 2});
  });

  test('sold-out and closed lines are never selectable', () {
    final container = _containerWith(
      _FakeCart([
        _item(1),
        _item(2, stock: 0),
        _item(3, status: ListingStatus.cancelled),
      ]),
    );
    expect(container.read(cartSelectionProvider), {1});
  });

  test('unticking survives a cart reload', () {
    // The cart refetches after every add, remove and quantity change, so a
    // selection that re-ticks itself would quietly re-add what the buyer
    // just cleared.
    final cart = _FakeCart([_item(1), _item(2)]);
    final container = _containerWith(cart);

    container.read(cartSelectionProvider.notifier).toggle(2);
    expect(container.read(cartSelectionProvider), {1});

    cart.emit([_item(1), _item(2)]);
    expect(container.read(cartSelectionProvider), {1});
  });

  test('a newly added line arrives selected', () {
    final cart = _FakeCart([_item(1)]);
    final container = _containerWith(cart);

    cart.emit([_item(1), _item(2)]);
    expect(container.read(cartSelectionProvider), {1, 2});
  });

  test('re-adding a removed listing comes back selected', () {
    // `cart_items.id` comes from a sequence, so a removed line never returns
    // under its old id — re-adding the same card creates a new row, and a
    // new row is not something the buyer has unticked.
    final cart = _FakeCart([_item(1), _item(2)]);
    final container = _containerWith(cart);

    container.read(cartSelectionProvider.notifier).toggle(2);
    expect(container.read(cartSelectionProvider), {1});

    cart.emit([_item(1)]);
    expect(container.read(cartSelectionProvider), {1});

    cart.emit([_item(1), _item(3)]);
    expect(container.read(cartSelectionProvider), {1, 3});
  });

  test('the seller checkbox toggles only that seller', () {
    final container = _containerWith(
      _FakeCart([_item(1), _item(2), _item(3, sellerId: 'seller-2')]),
    );

    container
        .read(cartSelectionProvider.notifier)
        .toggleSeller('seller-1', selected: false);
    expect(container.read(cartSelectionProvider), {3});
  });

  test('select-all clears and restores every available line', () {
    final container = _containerWith(
      _FakeCart([_item(1), _item(2), _item(3, stock: 0)]),
    );
    final notifier = container.read(cartSelectionProvider.notifier);

    notifier.toggleAll(selected: false);
    expect(container.read(cartSelectionProvider), isEmpty);

    notifier.toggleAll(selected: true);
    // Never the sold-out one.
    expect(container.read(cartSelectionProvider), {1, 2});
  });

  test('the selected items are what checkout is handed', () {
    // The regression this guards: the checkout page rendered the whole cart
    // while the notifier priced only the selection, so a buyer who picked
    // one of two lines saw two and was charged for one.
    final container = _containerWith(_FakeCart([_item(1), _item(2)]));

    expect(container.read(selectedCartItemsProvider), hasLength(2));

    container.read(cartSelectionProvider.notifier).toggle(2);

    final selected = container.read(selectedCartItemsProvider);
    expect(selected, hasLength(1));
    expect(selected.single.cartItemId, 1);
    // The cart itself is untouched — unticking is not removing.
    expect(container.read(cartProvider), hasLength(2));
  });

  test('the subtotal follows the selection, not the cart', () {
    final container = _containerWith(
      _FakeCart([_item(1, price: 50000, quantity: 2), _item(2, price: 30000)]),
    );
    expect(container.read(selectedSubtotalProvider), 130000);

    container.read(cartSelectionProvider.notifier).toggle(1);
    expect(container.read(selectedSubtotalProvider), 30000);
  });
}
