import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/postgrest_embed.dart';
import 'models/dispute_model.dart';
import 'models/order_model.dart';
import 'models/pending_checkout.dart';

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
      'order_items(slug, order_number, card_id, matched_quantity, match_price,'
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

    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      final counterparty = row[asSeller ? 'buyer_id' : 'seller_id'];
      return OrderModel.fromRow(
        row,
        storeName: names[counterparty] ?? (asSeller ? 'Pembeli' : 'Penjual'),
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

  Future<OrderModel?> fetchOrder(String slug) async {
    if (_uid == null) return null;

    final row = await _client
        .from('orders')
        .select(_orderColumns)
        .eq('slug', slug)
        .maybeSingle();
    if (row == null) return null;

    final sellerId = row['seller_id'] as String?;
    final names = await _sellerNames({if (sellerId != null) sellerId});
    return OrderModel.fromRow(row, storeName: names[sellerId] ?? 'Penjual');
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

  /// The dispute on an order, if one was opened. Disputes hang off the
  /// settlement rather than the order, so this walks the order's items.
  Future<DisputeModel?> fetchDispute(String orderSlug) async {
    if (_uid == null) return null;

    final order = await _client
        .from('orders')
        .select('id, slug, order_items(id)')
        .eq('slug', orderSlug)
        .maybeSingle();
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
