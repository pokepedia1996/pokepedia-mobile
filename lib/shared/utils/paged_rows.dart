import 'dart:math';

/// How many cards a collection may carry into the app.
///
/// PostgREST answers at most a page at a time — Supabase's "Max rows" is
/// 1000 by default — and a query with no `range` silently stops there rather
/// than erroring. That is why a 8,495-card collection reported "1000 kartu
/// unik": not a chart limit, a truncated read that every total downstream
/// then agreed on.
const maxCollectionRows = 15000;

/// One page of a PostgREST read.
const _collectionPageSize = 1000;

/// Reads every row [page] describes, a page at a time, up to [max].
///
/// Client-side paging rather than a bigger `limit`: the server cap wins over
/// whatever the client asks for, so the only way past it is to ask again.
/// The query must be fully ordered, or a row can repeat across two pages
/// while another is skipped.
Future<List<Map<String, dynamic>>> pagedRows(
  Future<dynamic> Function(int from, int to) page, {
  int max = maxCollectionRows,
}) async {
  final all = <Map<String, dynamic>>[];
  for (var from = 0; from < max; from += _collectionPageSize) {
    final to = min(from + _collectionPageSize, max) - 1;
    final rows = await page(from, to);
    if (rows is! List || rows.isEmpty) break;
    all.addAll(rows.cast<Map<String, dynamic>>());
    // A short page is the last page — asking again would spend a round trip
    // to be told the same thing.
    if (rows.length < to - from + 1) break;
  }
  return all;
}
