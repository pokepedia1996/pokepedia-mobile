import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';

/// Why a buyer is cancelling — the four values
/// `/api/order-items/[slug]/cancel-request` accepts, in web's order and
/// wording (`cancel-order-modal.tsx`).
enum CancelReason {
  sellerUnresponsive('seller_unresponsive', 'Penjual tidak responsif'),
  changedMind('changed_mind', 'Berubah pikiran'),
  wrongItem('wrong_item', 'Salah pesan item'),
  other('other', 'Lainnya');

  const CancelReason(this.raw, this.label);

  final String raw;
  final String label;

  /// What web's modal opens on.
  static const fallback = CancelReason.changedMind;
}

/// Cancelling an order, through pokepedia.id rather than Postgres.
///
/// The `request_order_cancel` RPC is only half the job: when a cancellation
/// takes effect immediately the route also has to call off the Biteship
/// booking, and that needs a server key. Going straight to the RPC from here
/// would cancel the order in the database and leave a courier still coming
/// for the parcel, so the app uses the same route the website does.
class OrderCancelRepository {
  OrderCancelRepository(this._api);

  final PokepediaApi _api;

  /// Asks to cancel the whole package.
  ///
  /// Returns true when the cancellation is already done, false when it is now
  /// waiting on the seller — web branches its confirmation on the same
  /// `instant` flag. Errors arrive as [ApiException] carrying the route's own
  /// sentence ("Penjual sudah memproses pesanan" and friends), so there is no
  /// second translation table here.
  ///
  /// [itemSlug] is the `order_items` slug, not the order's: the route looks
  /// the match up by it and checks `bid_user_id` against the caller.
  Future<bool> requestCancel({
    required String itemSlug,
    required CancelReason reason,
    String? detail,
  }) async {
    final trimmed = detail?.trim();
    final response = await _api.post(
      '/api/order-items/$itemSlug/cancel-request',
      {
        'reason': reason.raw,
        // Web sends the whole package from this button; per-item cancelling
        // is a separate flow it only offers on multi-item orders.
        'scope': 'package',
        if (trimmed != null && trimmed.isNotEmpty) 'detail': trimmed,
      },
    );
    return response['instant'] == true;
  }
}

final orderCancelRepositoryProvider = Provider(
  (ref) => OrderCancelRepository(ref.read(pokepediaApiProvider)),
);
