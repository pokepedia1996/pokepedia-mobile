import '../../../../shared/models/listing_model.dart';

/// Where the previous page of the marketplace feed stopped.
///
/// `get_recent_marketplace_listings` takes all three together: which one it
/// actually compares depends on `p_sort`, and its keyset clause has no
/// "null cursor" escape for the price sorts — a partial cursor fails closed
/// and returns nothing. So the last row's id, timestamp and price all travel.
class MarketCursor {
  const MarketCursor({
    required this.id,
    required this.createdAt,
    required this.price,
  });

  final int id;
  final DateTime createdAt;
  final int price;
}

/// One page of the feed, plus what is needed to ask for the next.
class MarketListingsPage {
  const MarketListingsPage({
    required this.listings,
    required this.hasNext,
    required this.cursor,
  });

  const MarketListingsPage.empty()
    : listings = const [],
      hasNext = false,
      cursor = null;

  /// The rows to show — already stripped of the viewer's own listings.
  final List<ListingModel> listings;

  /// Whether the server had a full page to give. Decided before own-listings
  /// are dropped, so a page left short by filtering is not mistaken for the
  /// end of the feed.
  final bool hasNext;

  /// Null when the page came back empty, which is also when [hasNext] is
  /// false — there is nothing to continue from.
  final MarketCursor? cursor;
}
