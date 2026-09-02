import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/postgrest_embed.dart';
import 'models/dispute_model.dart';
import 'models/order_model.dart';
import 'models/order_ref.dart';
import 'models/pending_checkout.dart';
import 'models/seller_order_detail.dart';

/// The card columns [OrderItemModel] needs, matching what
/// `expansions_repository.dart` selects so both build the same [CardModel].
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, '
    'image_url, illustrator, regulation_mark, language, variant, details';

/// Data access for Orders + Disputes.
///
/// Everything here is reachable with the caller's own token: `orders_select_own`
/// (buyer or seller), `order_items_select_own`, `settlements_select`,
/// `shipments_select` and `disputes_party_read` all scope to the parties of
/// the order. Store names are the exception — `seller_profiles` is
/// self-select only — so those come from `get_store_identities`.
class OrdersRepository {
  OrdersRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Kept on one line: PostgREST takes `select` as a query parameter.
  static const _orderColumns =
      'id, slug, order_number, status, created_at, seller_id, buyer_id,'
      'order_items(id, slug, order_number, card_id, matched_quantity, match_price,'
      'status, created_at, cards($_cardColumns),'
      'settlements(condition, escrow_amount, shipping_cost, status,'
      'paid_at, payment_deadline, cancel_status, cancel_reason),'
      // Only an active dispute changes what the seller sees; the filter is
      // applied client-side because a settled one still has to be readable
      // from the order detail page.
      'disputes(slug, current_status)),'
      // Named FK, not a bare `shipments`: orders links to shipments twice
      // (`shipments.order_id` and `orders.shipment_id`), and PostgREST
      // refuses an ambiguous embed with PGRST201 rather than picking one.
      'shipments!shipments_order_id_fkey(tracking_number, courier, status,'
      'shipped_at, delivered_at, shipment_deadline, biteship_order_id,'
      'biteship_book_error, origin_collection_method, status_history)';

  /// The caller's orders. As a buyer by default; [asSeller] flips it to the
  /// ones they're selling, which `orders_select_own` covers too — the policy
  /// is `buyer_id = auth.uid() OR seller_id = auth.uid()`.
  Future<List<OrderModel>> fetchOrders({
    int limit = 50,
    bool asSeller = false,
  }) async {
    final me = _uid;
    if (me == null) return const [];

    final rows =
        await _client
                .from('orders')
                .select(_orderColumns)
                .eq(asSeller ? 'seller_id' : 'buyer_id', me)
                .order('created_at', ascending: false)
                .limit(limit)
            as List;
    if (rows.isEmpty) return const [];

    // Whoever is on the other side of the order: the shop when you bought,
    // the person when you sold.
    final counterpartyIds = rows
        .map(
          (r) =>
              (r as Map<String, dynamic>)[asSeller ? 'buyer_id' : 'seller_id']
                  as String?,
        )
        .whereType<String>()
        .toSet();
    final names = asSeller
        ? await _usernames(counterpartyIds)
        : await _sellerNames(counterpartyIds);
    // The card's header shows a store logo, an `@username` and a link, so
    // the identity is resolved alongside the name — two batched queries for
    // the whole page rather than one per row.
    final identities = asSeller
        ? const <String, _SellerIdentity>{}
        : await _sellerIdentities(counterpartyIds);

    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      final counterparty = row[asSeller ? 'buyer_id' : 'seller_id'] as String?;
      final order = OrderModel.fromRow(
        row,
        storeName: names[counterparty] ?? (asSeller ? 'Pembeli' : 'Penjual'),
      );
      final identity = identities[counterparty];
      if (identity == null) return order;
      return order.withSeller(
        username: identity.username,
        avatarUrl: identity.avatarUrl,
        logoUrl: identity.logoUrl,
        slug: identity.slug,
      );
    }).toList();
  }

  /// Checkouts the buyer started against this seller's listings but hasn't
  /// paid for — web's "Menunggu pembayaran" tab.
  ///
  /// These aren't `orders` rows yet: the order is created when the payment
  /// lands, so they only exist as pending carts. `list_seller_pending_cart_items`
  /// is SECURITY DEFINER and scopes to `auth.uid()`, which is why the app
  /// can read them without seeing anyone else's cart.
  Future<List<PendingCheckout>> fetchPendingCheckouts() async {
    if (_uid == null) return const [];

    final rows = await _client.rpc('list_seller_pending_cart_items') as List;
    // One row per cart line; the seller thinks in checkouts, so they're
    // folded back together the way web's `groupByCheckout` does.
    final byCart = <int, List<Map<String, dynamic>>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final cartId = (row['cart_id'] as num).toInt();
      byCart.putIfAbsent(cartId, () => []).add(row);
    }
    return byCart.values.map(PendingCheckout.fromRows).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// The buyer's own unpaid checkouts — what "Belum Bayar" actually is.
  ///
  /// There is no order until the webhook settles the payment, so an unpaid
  /// checkout lives in `carts` and nowhere else. `carts_select_own` scopes
  /// this to the caller, so it needs no server route.
  Future<List<PendingCheckout>> fetchMyPendingCheckouts({
    int limit = 20,
  }) async {
    final me = _uid;
    if (me == null) return const [];

    final rows =
        await _client
                .from('carts')
                .select(
                  'id, external_id, status, total_amount, expires_at,'
                  'created_at, invoice_url, cart_snapshot',
                )
                .eq('user_id', me)
                .eq('status', 'pending')
                // An expired cart is not payable: the stock is already back
                // on sale, so offering it would be a dead end.
                .gt('expires_at', DateTime.now().toUtc().toIso8601String())
                .order('created_at', ascending: false)
                .limit(limit)
            as List;

    return rows
        .cast<Map<String, dynamic>>()
        .map(pendingCheckoutFromCart)
        .toList();
  }

  /// Store logo and slug from `get_store_identities`, username and avatar
  /// from `profiles` — the two halves of what web's `resolveSellerDisplay`
  /// needs, neither of which is readable off `seller_profiles` by a buyer.
  Future<Map<String, _SellerIdentity>> _sellerIdentities(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};

    final stores = <String, Map<String, dynamic>>{};
    try {
      final rows =
          await _client.rpc(
                'get_store_identities',
                params: {'p_user_ids': ids.toList()},
              )
              as List;
      for (final row in rows.cast<Map<String, dynamic>>()) {
        stores[row['user_id'] as String] = row;
      }
    } on PostgrestException {
      // A missing storefront just means the username is what shows.
    }

    final profiles =
        await _client
                .from('profiles')
                .select('id, username, avatar_url')
                .inFilter('id', ids.toList())
            as List;

    return {
      for (final row in profiles.cast<Map<String, dynamic>>())
        row['id'] as String: _SellerIdentity(
          username: row['username'] as String?,
          avatarUrl: row['avatar_url'] as String?,
          logoUrl: stores[row['id']]?['store_logo_url'] as String?,
          slug: stores[row['id']]?['store_slug'] as String?,
        ),
    };
  }

  /// Usernames by id, straight off `profiles` — world-readable, unlike
  /// `seller_profiles`.
  Future<Map<String, String>> _usernames(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows =
        await _client
                .from('profiles')
                .select('id, username')
                .inFilter('id', ids.toList())
            as List;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        if ((row['username'] as String?)?.isNotEmpty ?? false)
          row['id'] as String: row['username'] as String,
    };
  }

  /// One order, by whatever an `/orders/<ref>` link carries — see
  /// [_orderRowByRef] for why that is more than one thing.
  Future<OrderModel?> fetchOrder(String ref) async {
    if (_uid == null) return null;

    final row = await _orderRowByRef(ref, _orderColumns);
    if (row == null) return null;

    final sellerId = row['seller_id'] as String?;
    final names = await _sellerNames({if (sellerId != null) sellerId});
    return OrderModel.fromRow(row, storeName: names[sellerId] ?? 'Penjual');
  }

  /// The `orders` row a reference names, whichever kind of reference it is.
  ///
  /// The app addresses an order by `orders.slug`, but the website addresses
  /// the same screen by *match* — `order_items.slug`, or an order number from
  /// either table — and its notification triggers write all of those into
  /// `action_url`. A tapped notification therefore arrives holding an id this
  /// table has never heard of, which is what "Gagal memuat pesanan" was.
  ///
  /// Order matters: `orders` is tried first because that is what every link
  /// the app makes itself carries, so the common path stays one query. Both
  /// slug columns are `uuid`, so a reference is matched by shape rather than
  /// by trying it against every column — comparing a uuid column to
  /// `ord-260901-a7k3p` is an error, not a miss.
  Future<Map<String, dynamic>?> _orderRowByRef(
    String ref,
    String columns, {
    String? sellerId,
  }) async {
    final needle = ref.trim();
    final kind = classifyOrderRef(needle);
    if (kind == OrderRefKind.unknown) return null;
    final isUuid = kind == OrderRefKind.slug;

    PostgrestFilterBuilder<PostgrestList> scoped(
      PostgrestFilterBuilder<PostgrestList> query,
    ) => sellerId == null ? query : query.eq('seller_id', sellerId);

    final direct = await scoped(
      isUuid
          ? _client.from('orders').select(columns).eq('slug', needle)
          : _client
                .from('orders')
                .select(columns)
                .eq('order_number', needle.toLowerCase()),
    ).maybeSingle();
    if (direct != null) return direct;

    // Not the package — try the item. `order_items_select_own` scopes this to
    // the caller the same way, so a reference to somebody else's order still
    // resolves to nothing.
    final item =
        await (isUuid
                ? _client
                      .from('order_items')
                      .select('order_id')
                      .eq('slug', needle)
                : _client
                      .from('order_items')
                      .select('order_id')
                      .eq('order_number', needle.toLowerCase()))
            .limit(1)
            .maybeSingle();
    final orderId = (item?['order_id'] as num?)?.toInt();
    if (orderId == null) return null;

    return scoped(
      _client.from('orders').select(columns).eq('id', orderId),
    ).maybeSingle();
  }

  /// The seller's own columns for one order: the settlement's money and the
  /// shipping destination, neither of which the buyer's view needs.
  ///
  /// A superset of [_orderColumns] rather than an addition to it — the buyer
  /// list would be paying for joins it never reads.
  static const _sellerOrderColumns =
      'id, slug, order_number, status, created_at, seller_id, buyer_id,'
      'order_items(id, slug, order_number, card_id, matched_quantity, match_price,'
      'status, created_at, cards($_cardColumns),'
      'settlements(condition, escrow_amount, shipping_cost, status,'
      'paid_at, payment_deadline, cancel_status, cancel_reason,'
      'commission_amount, seller_net_amount, insurance_premium_idr,'
      // Which dispatch methods this order's courier supports, and who it is
      // — the shipment sheet offers pickup or a manual resi accordingly.
      'available_collection_method, courier_company),'
      'disputes(slug, current_status)),'
      'shipments!shipments_order_id_fkey(slug, tracking_number, courier, status,'
      'shipped_at, delivered_at, shipment_deadline, biteship_order_id,'
      'biteship_book_error, origin_collection_method, status_history,'
      'destination_contact_name, destination_contact_phone,'
      'destination_full_address, destination_district, destination_city,'
      'destination_province, destination_postal_code)';

  /// One order as its seller — web's `/seller/orders/[matchId]`.
  ///
  /// Returns null when the row isn't this user's to sell: `orders_select_own`
  /// covers both sides, so a buyer opening a seller URL would otherwise get
  /// their own order back wearing the wrong screen.
  Future<SellerOrderDetail?> fetchSellerOrder(String ref) async {
    final me = _uid;
    if (me == null) return null;

    final row = await _orderRowByRef(ref, _sellerOrderColumns, sellerId: me);
    if (row == null) return null;

    final buyerId = row['buyer_id'] as String?;
    final usernames = await _usernames({if (buyerId != null) buyerId});
    final username = usernames[buyerId];

    return SellerOrderDetail.fromRow(
      row,
      order: OrderModel.fromRow(row, storeName: username ?? 'Pembeli'),
      buyerUsername: username,
    );
  }

  /// Store name per seller id, falling back to their username for a seller
  /// who hasn't set a shop up.
  Future<Map<String, String>> _sellerNames(Set<String> sellerIds) async {
    if (sellerIds.isEmpty) return const {};

    final names = <String, String>{};
    final identities =
        await _client.rpc(
              'get_store_identities',
              params: {'p_user_ids': sellerIds.toList()},
            )
            as List;
    for (final row in identities.cast<Map<String, dynamic>>()) {
      final name = row['store_name'] as String?;
      if (name != null && name.isNotEmpty) {
        names[row['user_id'] as String] = name;
      }
    }

    final missing = sellerIds.where((id) => !names.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final profiles =
          await _client
                  .from('profiles')
                  .select('id, username')
                  .inFilter('id', missing)
              as List;
      for (final row in profiles.cast<Map<String, dynamic>>()) {
        final username = row['username'] as String?;
        if (username != null && username.isNotEmpty) {
          names[row['id'] as String] = username;
        }
      }
    }
    return names;
  }

  /// Buyer confirms the package arrived, releasing the escrow.
  ///
  /// `confirm_receipt` refuses anything but a shipped settlement the courier
  /// has recorded as delivered, with no open dispute — [OrderModel]'s
  /// `canConfirmReceipt` mirrors those rules so the button only appears
  /// where the call would succeed.
  Future<String?> confirmReceipt(int orderItemId) async {
    if (_uid == null) return 'Sesi berakhir.';
    try {
      final result = await _client.rpc(
        'confirm_receipt',
        params: {'p_match_id': orderItemId},
      );
      if (result is! Map) return 'Gagal mengonfirmasi penerimaan.';
      if (result['ok'] == true || result['error'] == null) return null;

      return switch (result['error']) {
        'not_delivered_yet' => 'Paket belum tercatat sampai oleh kurir.',
        'dispute_open' => 'Ada komplain terbuka untuk pesanan ini.',
        'invalid_status' => 'Pesanan ini belum bisa dikonfirmasi.',
        'forbidden' => 'Kamu bukan pembeli pesanan ini.',
        _ => 'Gagal mengonfirmasi penerimaan.',
      };
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// The dispute on an order, if one was opened. Disputes hang off the
  /// settlement rather than the order, so this walks the order's items.
  /// The open dispute on an order, by any reference the order screens take
  /// — they watch this with whatever the link handed them.
  Future<DisputeModel?> fetchDispute(String orderSlug) async {
    if (_uid == null) return null;

    final order = await _orderRowByRef(orderSlug, 'id, slug, order_items(id)');
    if (order == null) return null;

    final itemIds = embeddedRows(
      order['order_items'],
    ).map((item) => (item['id'] as num).toInt()).toList();
    if (itemIds.isEmpty) return null;

    final row = await _client
        .from('disputes')
        .select(
          'slug, current_status, reason, reason_category, outcome, opened_at,'
          'response_deadline_at, proposed_refund_amount,'
          'dispute_events(event_type, actor_role, payload, created_at)',
        )
        .inFilter('order_item_id', itemIds)
        .order('opened_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;

    return DisputeModel.fromRow(row, orderSlug: orderSlug);
  }
}

/// The counterparty's display identity, assembled from the two sources a
/// buyer is allowed to read.
class _SellerIdentity {
  const _SellerIdentity({
    this.username,
    this.avatarUrl,
    this.logoUrl,
    this.slug,
  });

  final String? username;
  final String? avatarUrl;
  final String? logoUrl;
  final String? slug;
}
