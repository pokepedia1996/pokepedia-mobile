import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/device_fingerprint.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import 'models/cart_item.dart';

/// A business-rule rejection from `add_to_cart`/`remove_from_cart`, mirroring
/// the RPC error codes documented in `pokepedia-web/docs/reference/api/cart.md`
/// (`phone_not_verified`, `insufficient_quantity`, `cannot_buy_own_listing`,
/// `same_device_self_trade`, `pending_cart_for_this_listing`, etc).
///
/// An [ApiException], so `userFacingError` shows [message] rather than its
/// generic fallback.
class CartException extends ApiException {
  const CartException(String code, {this.available, String? serverMessage})
    : _serverMessage = serverMessage,
      super('', code: code);

  final int? available;

  /// The sentence `POST /api/cart` answered with, which already carries what
  /// [available] would have filled in ("Hanya 2 tersedia").
  final String? _serverMessage;

  @override
  String get code => super.code!;

  /// Indonesian, user-facing — the route's own sentence when it sent one,
  /// else its error-code → message table (`app/api/cart/route.ts`).
  @override
  String get message =>
      _serverMessage ??
      switch (code) {
        'unauthorized' => 'Sesi habis, login ulang',
        'invalid_quantity' => 'Jumlah tidak valid',
        'phone_not_verified' => 'Verifikasi nomor HP terlebih dahulu',
        'banned' => 'Akun kamu sedang diblokir',
        'order_not_found' => 'Listing tidak ditemukan',
        'order_not_available' => 'Listing sudah tidak tersedia',
        'not_an_ask_order' => 'Order bukan listing penjualan',
        'trading_disabled' => 'Kartu ini belum bisa diperdagangkan.',
        'cannot_buy_own_listing' => 'Tidak bisa membeli listing sendiri',
        'same_device_self_trade' =>
          'Tidak dapat membeli listing dari akun lain di perangkat yang sama.',
        'insufficient_quantity' => 'Hanya ${available ?? 0} tersedia',
        'pending_cart_for_this_listing' =>
          'Listing ini sudah ada di pembayaran tertunda',
        'not_found' => 'Item tidak ditemukan',
        _ => 'Gagal memproses keranjang',
      };
}

/// Data access for the Cart feature — mirrors `lib/cart/index.ts`'s
/// `fetchCart` over Supabase (RLS), and the `add_to_cart` /
/// `remove_from_cart` RPCs documented in
/// `pokepedia-web/docs/reference/api/cart.md`.
///
/// Adding goes through `POST /api/cart` rather than the RPC, so a mobile
/// add gets the route's per-user rate limit and its `recordDeviceUser` call
/// — with the request IP the app cannot see — before `add_to_cart` runs,
/// which is what the same-device self-trade guard joins on.
class CartRepository {
  CartRepository(this._client, this._api, this._fingerprint);

  final SupabaseClient _client;
  final PokepediaApi _api;
  final DeviceFingerprint _fingerprint;

  Future<List<CartItem>> fetchCart() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final cartRows = await _client
        .from('cart_items')
        .select('id, ask_order_id, quantity, added_at')
        .eq('user_id', userId)
        .order('added_at', ascending: false);
    if (cartRows.isEmpty) return const [];

    final askIds = cartRows
        .map((r) => r['ask_order_id'] as int)
        .toSet()
        .toList();

    final listingRows = await _client
        .from('listings')
        .select(
          'id, slug, side, price, condition, card_id, variant_key, quantity, '
          'qty_locked, status, accepts_offers, view_count, created_at, user_id',
        )
        .inFilter('id', askIds);
    if (listingRows.isEmpty) return const [];

    final cardIds = listingRows
        .map((r) => r['card_id'] as int)
        .toSet()
        .toList();
    final sellerIds = listingRows
        .map((r) => r['user_id'] as String)
        .toSet()
        .toList();

    final results = await Future.wait([
      _client
          .from('cards')
          .select(
            'id, category, name_id, expansion_code, collector_number, rarity, '
            'regulation_mark, illustrator, language, variant, details, image_url',
          )
          .inFilter('id', cardIds),
      _client
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', sellerIds),
    ]);
    final cardRows = results[0];
    final profileRows = results[1];

    // Storefront names, through `get_listings_by_ids` rather than off
    // `seller_profiles` directly.
    //
    // `seller_profiles` is granted to `authenticated`, so a direct read does
    // not error — it comes back *empty*, because the only SELECT policy on it
    // is `seller_profiles_self_select` (`auth.uid() = user_id`). A buyer can
    // read their own storefront and nobody else's, so every seller in the
    // cart fell through to their username: "Zedss__" where the store page
    // says "singlepoke.id".
    //
    // The RPC is `SECURITY DEFINER` and granted to `authenticated`, and it
    // already returns the store name, slug and logo joined per listing —
    // which is the same way the marketplace tiles and the store page get
    // them. Web reads the table with `service_role` instead
    // (`lib/cart/index.ts`); this is the app's equivalent.
    // Keyed by listing id, which is what the RPC takes and returns — it
    // carries no `user_id` column, and the listing already knows its seller.
    var storeByListing = <int, Map<String, dynamic>>{};
    try {
      final rows =
          await _client.rpc('get_listings_by_ids', params: {'p_ids': askIds})
              as List;
      storeByListing = {
        for (final raw in rows.whereType<Map<String, dynamic>>())
          if ((raw['id'] as num?)?.toInt() case final id?) id: raw,
      };
    } catch (_) {
      // Best effort: a failure here costs the shop name, not the cart.
    }

    final cardById = {
      for (final r in cardRows) r['id'] as int: CardModel.fromRow(r),
    };
    final profileById = {for (final r in profileRows) r['id'] as String: r};

    final listingById = <int, ListingModel>{};
    for (final row in listingRows) {
      final card = cardById[row['card_id'] as int];
      if (card == null) continue;
      final listingId = row['id'] as int;
      if (row['slug'] case final String slug) {
        _slugByListingId[listingId] = slug;
      }
      final sellerId = row['user_id'] as String;
      final profile = profileById[sellerId];
      final store = storeByListing[listingId];
      listingById[listingId] = ListingModel.fromRow(
        row,
        card: card,
        storeSlug: store?['store_slug'] as String?,
        storeName: store?['store_name'] as String?,
        sellerUsername: profile?['username'] as String?,
        // Neither is on the RPC, and the direct `seller_profiles` read they
        // used to come from returned nothing for another seller anyway — so
        // these were already false/blank here, not a regression.
        isVerified: false,
        cityName: '',
        sellerAvatarUrl: profile?['avatar_url'] as String?,
        storeLogoUrl: store?['store_logo_url'] as String?,
      );
    }

    final items = <CartItem>[];
    for (final row in cartRows) {
      final listing = listingById[row['ask_order_id'] as int];
      if (listing == null) continue;
      items.add(
        CartItem(
          cartItemId: row['id'] as int,
          listing: listing,
          quantity: row['quantity'] as int,
        ),
      );
    }
    return items;
  }

  /// `POST /api/cart`. [listingId] is `listings.id`; the route takes the
  /// listing's slug instead, so it is resolved first — from the last cart
  /// read when the listing is already in it.
  Future<void> add(int listingId, int quantity) async {
    final askOrderSlug =
        _slugByListingId[listingId] ?? await _slugOf(listingId);
    if (askOrderSlug == null) throw const CartException('order_not_found');

    String? deviceFingerprint;
    try {
      deviceFingerprint = await _fingerprint.value();
    } catch (_) {
      // Best effort: a missing fraud signal must never block the add.
    }

    try {
      await _api.post(
        '/api/cart',
        addToCartBody(
          askOrderSlug: askOrderSlug,
          quantity: quantity,
          deviceFingerprint: deviceFingerprint,
        ),
      );
    } on ApiException catch (e) {
      throw cartExceptionFromApi(e);
    }
  }

  /// The `AddToCartBodySchema` body.
  static Map<String, dynamic> addToCartBody({
    required String askOrderSlug,
    required int quantity,
    String? deviceFingerprint,
  }) => {
    'askOrderSlug': askOrderSlug,
    'quantity': quantity,
    if (deviceFingerprint != null) 'deviceFingerprint': deviceFingerprint,
  };

  final _slugByListingId = <int, String>{};

  Future<String?> _slugOf(int listingId) async {
    final row = await _client
        .from('listings')
        .select('slug')
        .eq('id', listingId)
        .maybeSingle();
    final slug = row?['slug'] as String?;
    if (slug != null) _slugByListingId[listingId] = slug;
    return slug;
  }

  Future<void> remove(int cartItemId) async {
    final result =
        await _client.rpc(
              'remove_from_cart',
              params: {'p_cart_item_id': cartItemId},
            )
            as Map<String, dynamic>?;
    final error = result?['error'] as String?;
    if (error != null) throw CartException(error);
  }

  /// Runs the same `validate_cart` RPC the web checkout route calls first,
  /// so a listing that sold out or was cancelled is caught in the app
  /// instead of failing inside the payment WebView. Returns one message per
  /// unusable line, empty when the cart is good to go.
  /// [only] limits the check to those `cart_items.id`s. The RPC always
  /// validates the whole cart, but a line the buyer didn't select isn't
  /// their problem right now — blocking checkout because something they
  /// left behind sold out would be nonsense.
  Future<List<String>> validate({Set<int>? only}) async {
    final result = await _client.rpc('validate_cart') as Map<String, dynamic>?;
    if (result == null) return const [];
    if (result['error'] != null) return const ['Masuk dulu untuk checkout.'];

    final invalid = (result['invalid_items'] as List?) ?? const [];
    return invalid
        .whereType<Map<String, dynamic>>()
        .where((item) {
          if (only == null) return true;
          final id = (item['cart_item_id'] as num?)?.toInt();
          return id != null && only.contains(id);
        })
        .map(
          (item) => cartLineProblemMessage(
            item['reason'] as String?,
            available: (item['available'] as num?)?.toInt(),
          ),
        )
        .toList();
  }
}

/// One sentence for a cart line `validate_cart` refused, keyed by its
/// `reason`. Shared by the pre-submit check and the `droppedItems` that
/// `/api/cart/checkout` reports, which carry the same reasons.
String cartLineProblemMessage(String? reason, {int? available}) {
  switch (reason) {
    case 'order_not_found':
    case 'listing_cancelled':
      return 'Satu listing sudah dibatalkan penjual.';
    case 'listing_expired':
      return 'Satu listing sudah kedaluwarsa.';
    case 'listing_matched':
      return 'Satu listing sudah terjual.';
    case 'not_an_ask_order':
      return 'Satu item bukan listing yang bisa dibeli.';
    case 'seller_on_vacation':
      return 'Penjual sedang libur, satu item tidak bisa diproses.';
    case 'insufficient_quantity':
      return 'Stok satu listing tinggal ${available ?? 0}.';
    default:
      return 'Satu item di keranjang tidak bisa diproses.';
  }
}

/// Maps a `POST /api/cart` refusal back onto the RPC's codes, so callers keep
/// branching on [CartException] as they did when the RPC was called direct.
///
/// Business refusals arrive as `400 {error: <kalimat>, code}`; the slug
/// lookup's miss is a code-less 404, and a lost session is the transport's
/// own [ApiAuthException].
CartException cartExceptionFromApi(ApiException e) {
  if (e is ApiAuthException) return const CartException('unauthorized');
  final code =
      e.code ?? (e.statusCode == 404 ? 'order_not_found' : 'add_failed');
  final stated = e.message.trim();
  return CartException(
    code,
    serverMessage: stated.isEmpty || stated == ApiException.genericMessage
        ? null
        : stated,
  );
}
