/// Reading PostgREST's embedded rows without assuming their shape.
///
/// PostgREST returns an *object* for a one-to-one embed and an *array* for
/// one-to-many, and which one you get depends on whether the foreign key
/// column happens to be unique. `settlements.order_item_id` is unique
/// (`settlements_order_item_id_key`) so it arrives as an object;
/// `shipments.order_id` isn't, so it arrives as an array. Casting to one
/// shape breaks the moment a constraint is added or dropped — which is
/// exactly how the orders page started failing with
/// `_Map<String, dynamic> is not a subtype of List<dynamic>`.
library;

/// The first embedded row, whichever shape it arrived in.
Map<String, dynamic>? embeddedRow(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) return Map<String, dynamic>.from(entry);
    }
  }
  return null;
}

/// Every embedded row, whichever shape they arrived in.
List<Map<String, dynamic>> embeddedRows(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
  if (value is Map) return [Map<String, dynamic>.from(value)];
  return const [];
}
