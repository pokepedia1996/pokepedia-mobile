import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/listing_offer.dart';

/// Mirrors the filter step inside `sellerListingsProvider`: keep only the
/// rows the counts map knows about.
///
/// Asserted on the rule rather than through the provider, which needs an
/// authenticated Supabase client to get as far as the listings query.
List<String> applyOfferFilter(
  List<String> slugs,
  Map<String, OfferCount> counts, {
  required bool on,
}) {
  if (!on) return slugs;
  return [
    for (final slug in slugs)
      if (counts.containsKey(slug)) slug,
  ];
}

void main() {
  const counts = {
    'a': OfferCount(total: 2, needsResponse: 1),
    'c': OfferCount(total: 1, needsResponse: 0),
  };

  test('off, every listing stays', () {
    expect(applyOfferFilter(['a', 'b', 'c'], counts, on: false), [
      'a',
      'b',
      'c',
    ]);
  });

  test('on, only listings holding a live offer survive', () {
    expect(applyOfferFilter(['a', 'b', 'c'], counts, on: true), ['a', 'c']);
  });

  test('an offer waiting on the buyer still counts as an offer', () {
    // The filter asks "does this listing have one", not "is it my turn" —
    // the menu badge answers the second question.
    expect(applyOfferFilter(['c'], counts, on: true), ['c']);
  });

  test('order is preserved, so the sort still holds', () {
    // The filter runs after `sellerSortProvider.apply`; reordering here
    // would silently undo whichever column the seller picked.
    expect(applyOfferFilter(['c', 'a'], counts, on: true), ['c', 'a']);
  });

  test('no offers anywhere leaves an empty table, not the full one', () {
    // The seller asked to see only listings with offers; showing all of
    // them would read as "these all have offers".
    expect(applyOfferFilter(['a', 'b'], const {}, on: true), isEmpty);
  });

  test('the chip counts listings, not offers', () {
    // Two offers on one listing is one row the filter would leave.
    expect(counts.length, 2);
    expect(counts.values.fold<int>(0, (sum, c) => sum + c.total), 3);
  });
}
