import '../../../../shared/models/card_model.dart';

/// One `user_inventory` row (draft or confirmed), joined with its card.
/// Ports `InventoryRow` from `lib/products/inventory.ts` — trimmed to the
/// fields the mobile app actually surfaces (no custom columns).
class InventoryEntry {
  const InventoryEntry({
    required this.id,
    required this.card,
    required this.quantity,
    required this.unitPrice,
    required this.createdAt,
    this.notes,
  });

  final int id;
  final CardModel card;
  final int quantity;
  final int unitPrice;
  final DateTime createdAt;
  final String? notes;

  int get totalValue => quantity * unitPrice;
}

enum InventoryActivityAction { addedIn, removedOut, updated }

extension InventoryActivityActionX on InventoryActivityAction {
  static InventoryActivityAction fromRaw(String raw) => switch (raw) {
    'in' => InventoryActivityAction.addedIn,
    'out' => InventoryActivityAction.removedOut,
    _ => InventoryActivityAction.updated,
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
  });

  final int id;
  final CardModel card;
  final InventoryActivityAction action;
  final int quantity;
  final int unitPrice;
  final DateTime createdAt;
}
