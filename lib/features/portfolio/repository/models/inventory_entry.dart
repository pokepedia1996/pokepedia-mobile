import '../../../../shared/models/card_model.dart';

/// One `user_inventory` row (draft or confirmed), joined with its card.
/// Ports `InventoryRow` from `features/inventory/api/inventory.ts`.
class InventoryEntry {
  const InventoryEntry({
    required this.id,
    required this.card,
    required this.quantity,
    required this.unitPrice,
    required this.createdAt,
    this.notes,
    this.series,
    this.seriesId,
    this.variantKey,
    this.customData = const {},
    this.source,
  });

  final int id;
  final CardModel card;
  final int quantity;
  final int unitPrice;
  final DateTime createdAt;
  final String? notes;

  /// The expansion's series by name — "Scarlet & Violet" — and its id,
  /// which is what web sorts the Seri column by: release order, not A–Z.
  final String? series;
  final int? seriesId;

  /// Which finish of the card this copy is, when the row names one.
  final String? variantKey;

  /// The values of the user's own columns, keyed by `column_key`.
  final Map<String, Object?> customData;

  /// Where the row came from — `sync` for one staged by "Sinkronkan
  /// Koleksi", which was copied out of the collection.
  final String? source;

  /// A synced draft is already in the collection: saving it must not add
  /// it there a second time. Web's `splitDraftsBySource`.
  bool get isSynced => source == 'sync';

  /// The row after an edit was saved, without reading it back.
  InventoryEntry copyWith({int? quantity, int? unitPrice, String? notes}) =>
      InventoryEntry(
        id: id,
        card: card,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        createdAt: createdAt,
        notes: notes ?? this.notes,
        series: series,
        seriesId: seriesId,
        variantKey: variantKey,
        customData: customData,
        source: source,
      );

  int get totalValue => quantity * unitPrice;
}

enum InventoryActivityAction { addedIn, removedOut, updated }

extension InventoryActivityActionX on InventoryActivityAction {
  static InventoryActivityAction fromRaw(String raw) => switch (raw) {
    'in' => InventoryActivityAction.addedIn,
    'out' => InventoryActivityAction.removedOut,
    _ => InventoryActivityAction.updated,
  };

  /// Web's word for it: Masuk, Keluar, or Perbaikan for a correction.
  String get label => switch (this) {
    InventoryActivityAction.addedIn => 'Masuk',
    InventoryActivityAction.removedOut => 'Keluar',
    InventoryActivityAction.updated => 'Perbaikan',
  };
}

/// One `user_inventory_activity` row — a read-only audit trail entry.
/// Ports `InventoryActivityRow` from `lib/products/inventory.ts`.
class InventoryActivityEntry {
  const InventoryActivityEntry({
    required this.id,
    required this.card,
    required this.action,
    required this.quantity,
    required this.unitPrice,
    required this.createdAt,
    this.variantKey,
    this.series,
    this.seriesId,
  });

  final int id;
  final CardModel card;
  final InventoryActivityAction action;
  final int quantity;
  final int unitPrice;
  final DateTime createdAt;

  /// Which finish the movement was of, as [InventoryEntry.variantKey].
  final String? variantKey;

  /// The expansion's series, as [InventoryEntry.series].
  final String? series;
  final int? seriesId;
}

/// One row of `user_inventory_column_config` — which of the Database tab's
/// columns the user shows, and the ones they added themselves. Ports
/// `ColumnConfig`; the app reads it and leaves editing to web.
class InventoryColumn {
  const InventoryColumn({
    required this.key,
    required this.label,
    required this.isVisible,
    required this.isCustom,
    required this.isNumber,
  });

  factory InventoryColumn.fromRow(Map<String, dynamic> row) => InventoryColumn(
    key: row['column_key'] as String,
    label: row['label'] as String? ?? row['column_key'] as String,
    isVisible: row['is_visible'] as bool? ?? true,
    isCustom: row['is_custom'] as bool? ?? false,
    isNumber: row['data_type'] == 'number',
  );

  final String key;
  final String label;
  final bool isVisible;
  final bool isCustom;

  /// Sorted as numbers rather than text — so 10 comes after 9.
  final bool isNumber;
}
