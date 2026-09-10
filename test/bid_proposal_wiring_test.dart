import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/expansions/repository/trading_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The bid detail page answers a wanted-ad through `submit_bid_proposal`,
/// which refuses in ways the order book's broadcast never could — it names
/// one bid, so it can be your own, already answered, or short on stock.
/// An unmapped code surfaces as "Gagal mengirim proposal", which tells the
/// seller nothing about what to change.
void main() {
  // Built directly rather than through the provider: the lookup is pure, and
  // reaching for `Supabase.instance` would need the whole SDK initialised to
  // read a string table.
  final repository = TradingRepository(
    SupabaseClient('http://localhost:54321', 'anon-key'),
  );

  test('every submit_bid_proposal refusal has seller-facing copy', () {
    // The codes `submit_bid_proposal` returns, in the order the function
    // checks them.
    const codes = [
      'unauthorized',
      'invalid_quantity',
      'invalid_photos',
      'phone_not_verified',
      'seller_profile_incomplete',
      'no_couriers',
      'order_not_found',
      'order_not_available',
      'not_a_bid_order',
      'trading_disabled',
      'cannot_propose_on_own_bid',
      'insufficient_quantity',
      'condition_mismatch',
      'invalid_proposed_price',
      'proposal_already_pending',
    ];

    for (final code in codes) {
      expect(
        repository.debugMessageFor(code),
        isNot('Gagal mengirim proposal'),
        reason: '$code has no seller-facing message',
      );
    }
  });

  test('the broadcast codes still map', () {
    // The two RPCs share this table; adding the single-bid codes must not
    // have cost the order book its own wording.
    expect(
      repository.debugMessageFor('no_bids'),
      'Tidak ada bid di harga ini lagi',
    );
    expect(
      repository.debugMessageFor('rate_limited'),
      'Terlalu banyak proposal. Coba lagi nanti.',
    );
  });

  test('answering your own bid is named, not left generic', () {
    // The page disables the button for an own bid, but a stale page can
    // still send one — and "coba lagi" would be wrong advice.
    expect(
      repository.debugMessageFor('cannot_propose_on_own_bid'),
      'Ini bid kamu sendiri',
    );
  });

  test('an unknown code still says something', () {
    expect(
      repository.debugMessageFor('something_new'),
      'Gagal mengirim proposal',
    );
  });
}
