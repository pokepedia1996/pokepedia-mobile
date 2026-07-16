import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// `orders.status` check constraint — the shipment-level status shown on
/// the buyer's order list.
enum OrderStatus { awaitingShipment, shipped, received, completed, cancelled, issue }

extension OrderStatusX on OrderStatus {
  String get raw {
    switch (this) {
      case OrderStatus.awaitingShipment:
        return 'awaiting_shipment';
      case OrderStatus.shipped:
        return 'shipped';
      case OrderStatus.received:
        return 'received';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.issue:
        return 'issue';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.awaitingShipment:
        return 'Menunggu Dikirim';
      case OrderStatus.shipped:
        return 'Dikirim';
      case OrderStatus.received:
        return 'Diterima';
      case OrderStatus.completed:
        return 'Selesai';
      case OrderStatus.cancelled:
        return 'Dibatalkan';
      case OrderStatus.issue:
        return 'Bermasalah';
    }
  }
}

/// `order_items.status` check constraint — the per-line-item lifecycle
/// (escrow acceptance -> payment hold -> release).
enum OrderItemStatus {
  pendingAcceptance,
  accepted,
  inEscrow,
  completed,
  cancelled,
  rejected,
  expired,
}

extension OrderItemStatusX on OrderItemStatus {
  String get label {
    switch (this) {
      case OrderItemStatus.pendingAcceptance:
        return 'Menunggu Konfirmasi Penjual';
      case OrderItemStatus.accepted:
        return 'Dikonfirmasi Penjual';
      case OrderItemStatus.inEscrow:
        return 'Dana Ditahan (Escrow)';
      case OrderItemStatus.completed:
        return 'Selesai';
      case OrderItemStatus.cancelled:
        return 'Dibatalkan';
      case OrderItemStatus.rejected:
        return 'Ditolak';
      case OrderItemStatus.expired:
        return 'Kedaluwarsa';
    }
  }
}

class OrderItemModel {
  const OrderItemModel({
    required this.slug,
    required this.orderNumber,
    required this.card,
    required this.condition,
    required this.matchedQuantity,
    required this.matchPrice,
    required this.status,
    required this.createdAt,
  });

  final String slug;
  final String orderNumber;
  final CardModel card;
  final CardCondition condition;
  final int matchedQuantity;
  final int matchPrice;
  final OrderItemStatus status;
  final DateTime createdAt;

  int get subtotal => matchPrice * matchedQuantity;
}

/// A buyer order, mirroring `public.orders` joined with its
/// `public.order_items` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class OrderModel {
  const OrderModel({
    required this.slug,
    required this.orderNumber,
    required this.storeName,
    required this.status,
    required this.createdAt,
    required this.items,
    this.trackingNumber,
    this.courier,
  });

  final String slug;
  final String orderNumber;
  final String storeName;
  final OrderStatus status;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  final String? trackingNumber;
  final String? courier;

  int get total => items.fold(0, (sum, item) => sum + item.subtotal);
}
