import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import 'models/cart_item.dart';

/// A business-rule rejection from `add_to_cart`/`remove_from_cart`, mirroring
/// the RPC error codes documented in `pokepedia-web/docs/reference/api/cart.md`
/// (`phone_not_verified`, `insufficient_quantity`, `cannot_buy_own_listing`,
/// `same_device_self_trade`, `pending_cart_for_this_listing`, etc).
class CartException implements Exception {
  const CartException(this.code, {this.available});

  final String code;
  final int? available;

  /// Indonesian, user-facing — mirrors the route's error-code → message
  /// table (`app/api/cart/route.ts`) since the RPC is called directly here
  /// rather than through that route.
  String get message => switch (code) {
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

/// Data access for the Cart feature, backed directly by Supabase (RLS) —
/// mirrors `lib/cart/index.ts`'s `fetchCart` and the `add_to_cart` /
/// `remove_from_cart` RPCs documented in
/// `pokepedia-web/docs/reference/api/cart.md`. Unlike the web, this calls
/// the RPCs directly instead of through `/api/cart` (that route only
/// authenticates via browser cookies, unreachable from a native client) —
/// the trade-off is losing that route's per-user Redis rate limit and
/// device-fingerprint self-trade linking for mobile-originated cart writes;
/// the RPC's own stock/self-trade/phone-verify/ban checks still apply since
/// those live in SQL, not the route.
class CartRepository {
  CartRepository(this._client);

  final SupabaseClient _client;

  Future<List<CartItem>> fetchCart() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final cartRows = await _client
        .from('cart_items')
        .select('id, ask_order_id, quantity, added_at')
        .eq('user_id', userId)
        .order('added_at', ascending: false);
    if (cartRows.isEmpty) return const [];

    final askIds = cartRows.map((r) => r['ask_order_id'] as int).toSet().toList();

    final listingRows = await _client
        .from('listings')
        .select(
          'id, slug, side, price, condition, card_id, variant_key, quantity, '
          'qty_locked, status, accepts_offers, view_count, created_at, user_id',
        )
        .inFilter('id', askIds);
    if (listingRows.isEmpty) return const [];

    final cardIds = listingRows.map((r) => r['card_id'] as int).toSet().toList();
    final sellerIds = listingRows.map((r) => r['user_id'] as String).toSet().toList();

    final results = await Future.wait([
      _client
          .from('cards')
          .select(
            'id, category, name_id, expansion_code, collector_number, rarity, '
            'regulation_mark, illustrator, language, variant, details, image_url',
          )
          .inFilter('id', cardIds),
      _client.from('profiles').select('id, username, avatar_url').inFilter('id', sellerIds),
    ]);
    final cardRows = results[0];
    final profileRows = results[1];

    // Best-effort storefront enrichment (name/logo/city/verified badge) —
    // `seller_profiles` may or may not be directly readable by a buyer under
    // RLS (the web only ever reads it via the service role); fall back to
    // the seller's public username if this comes back empty or errors.
    var storeById = <String, Map<String, dynamic>>{};
    try {
      final storeRows = await _client
          .from('seller_profiles')
          .select('user_id, store_name, store_slug, store_logo_url, city_name, is_verified')
          .inFilter('user_id', sellerIds);
      storeById = {for (final r in storeRows) r['user_id'] as String: r};
    } catch (_) {
      // Swallowed — falls back to username-based display below.
    }

    final cardById = {for (final r in cardRows) r['id'] as int: CardModel.fromRow(r)};
    final profileById = {for (final r in profileRows) r['id'] as String: r};

    final listingById = <int, ListingModel>{};
    for (final row in listingRows) {
      final card = cardById[row['card_id'] as int];
      if (card == null) continue;
      final sellerId = row['user_id'] as String;
      final profile = profileById[sellerId];
      final store = storeById[sellerId];
      final username = profile?['username'] as String? ?? 'Pengguna';
      listingById[row['id'] as int] = ListingModel.fromRow(
        row,
        card: card,
        storeSlug: (store?['store_slug'] as String?) ?? username,
        storeName: (store?['store_name'] as String?) ?? '@$username',
        isVerified: (store?['is_verified'] as bool?) ?? false,
        cityName: (store?['city_name'] as String?) ?? '',
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

  /// Mirrors `POST /api/cart`'s `rpc("add_to_cart", { p_ask_order_id, p_quantity })`
  /// — [listingId] is `listings.id` (already the internal integer id on
  /// [ListingModel], no slug resolution needed since the mobile client
  /// already has it).
  Future<void> add(int listingId, int quantity) async {
    final result =
        await _client.rpc(
              'add_to_cart',
              params: {'p_ask_order_id': listingId, 'p_quantity': quantity},
            )
            as Map<String, dynamic>?;
    final error = result?['error'] as String?;
    if (error != null) {
      throw CartException(error, available: (result?['available'] as num?)?.toInt());
    }
  }

  Future<void> remove(int cartItemId) async {
    final result =
        await _client.rpc('remove_from_cart', params: {'p_cart_item_id': cartItemId})
            as Map<String, dynamic>?;
    final error = result?['error'] as String?;
    if (error != null) throw CartException(error);
  }
}
