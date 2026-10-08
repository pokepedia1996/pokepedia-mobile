/// Rows per request when walking a list to its end.
const proposalsPageSize = 50;

/// Hard stop on how many pages one walk will request, so a list that keeps
/// growing under the walk can't keep it going forever.
const proposalsMaxPages = 20;

/// Ports `fetchAllBuyerBids`: requests pages until one comes back short,
/// de-duplicating by [keyOf] in case a row shifts across a page boundary
/// mid-walk.
///
/// [fetchPage] receives an inclusive `from`/`to` row range, the shape
/// PostgREST's `.range` takes.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int from, int to) fetchPage, {
  required String Function(T row) keyOf,
  int pageSize = proposalsPageSize,
  int maxPages = proposalsMaxPages,
}) async {
  final byKey = <String, T>{};
  for (var page = 0; page < maxPages; page++) {
    final from = page * pageSize;
    final rows = await fetchPage(from, from + pageSize - 1);
    for (final row in rows) {
      byKey[keyOf(row)] = row;
    }
    if (rows.length < pageSize) break;
  }
  return byKey.values.toList();
}
