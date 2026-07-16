import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_condition.dart';
import 'models/dispute_model.dart';
import 'models/order_model.dart';

/// Data access for the Orders + Disputes feature. Stands in for the web's
/// `orders` / `order_items` / `disputes` / `dispute_events` Supabase
/// queries while this pass only ports the UI with dummy data.
class OrdersRepository {
  static final List<OrderModel> _orders = _seed();
  static final Map<String, DisputeModel> _disputes = _seedDisputes();

  static List<OrderModel> _seed() {
    final cards = DummyCatalog.allCards.take(6).toList();
    final itemStatuses = OrderItemStatus.values;
    final now = DateTime(2026, 7, 16);
    return List.generate(cards.length, (i) {
      final card = cards[i];
      final store = DummyCatalog.stores[i % DummyCatalog.stores.length];
      final orderNumber = 'PKP-${20260700 + i}';
      final itemStatus = itemStatuses[i % itemStatuses.length];
      // orders.status is driven off the (single, for this dummy pass)
      // order_item's lifecycle so the two stay consistent, mirroring how
      // the real shipment/escrow flow keeps them in lockstep.
      final orderStatus = switch (itemStatus) {
        OrderItemStatus.pendingAcceptance || OrderItemStatus.accepted => OrderStatus.awaitingShipment,
        OrderItemStatus.inEscrow => OrderStatus.shipped,
        OrderItemStatus.completed => OrderStatus.completed,
        OrderItemStatus.cancelled || OrderItemStatus.rejected => OrderStatus.cancelled,
        OrderItemStatus.expired => OrderStatus.issue,
      };
      return OrderModel(
        slug: 'ord-${(1000 + i).toString()}',
        orderNumber: orderNumber,
        storeName: store.storeName,
        status: orderStatus,
        createdAt: now.subtract(Duration(days: i + 1)),
        trackingNumber: itemStatus == OrderItemStatus.inEscrow || itemStatus == OrderItemStatus.completed
            ? 'JX${100000 + i}ID'
            : null,
        courier: itemStatus == OrderItemStatus.inEscrow || itemStatus == OrderItemStatus.completed
            ? 'JNE Reguler'
            : null,
        items: [
          OrderItemModel(
            slug: 'oi-${1000 + i}',
            orderNumber: orderNumber,
            card: card,
            condition: CardCondition.values[i % rawConditions.length],
            matchedQuantity: 1 + (i % 3),
            matchPrice: card.marketPrice ?? 25000,
            status: itemStatus,
            createdAt: now.subtract(Duration(days: i + 1)),
          ),
        ],
      );
    });
  }

  static Map<String, DisputeModel> _seedDisputes() {
    final now = DateTime(2026, 7, 16);
    final issueOrder = _orders.firstWhere(
      (o) => o.status == OrderStatus.issue,
      orElse: () => _orders.first,
    );
    return {
      issueOrder.slug: DisputeModel(
        slug: 'dsp-1001',
        orderSlug: issueOrder.slug,
        currentStatus: DisputeStatus.awaitingSeller,
        reasonCategory: DisputeReasonCategory.notAsDescribed,
        reason:
            'Kondisi kartu yang diterima tidak sesuai dengan foto listing — terdapat whitening di sudut kartu yang tidak disebutkan penjual.',
        openedAt: now.subtract(const Duration(days: 1, hours: 4)),
        responseDeadline: now.add(const Duration(hours: 20)),
        events: [
          DisputeEvent(
            type: DisputeEventType.opened,
            actorRole: 'buyer',
            description: 'Pembeli membuka sengketa: Barang tidak sesuai deskripsi.',
            createdAt: now.subtract(const Duration(days: 1, hours: 4)),
          ),
          DisputeEvent(
            type: DisputeEventType.evidenceSubmitted,
            actorRole: 'buyer',
            description: 'Pembeli mengunggah 3 foto bukti kondisi kartu.',
            createdAt: now.subtract(const Duration(days: 1, hours: 3)),
          ),
          DisputeEvent(
            type: DisputeEventType.statusChanged,
            actorRole: 'system',
            description: 'Menunggu respons penjual dalam 24 jam.',
            createdAt: now.subtract(const Duration(days: 1, hours: 3)),
          ),
        ],
      ),
    };
  }

  Future<List<OrderModel>> fetchOrders() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _orders;
  }

  Future<OrderModel?> fetchOrder(String slug) async {
    await Future.delayed(const Duration(milliseconds: 150));
    for (final o in _orders) {
      if (o.slug == slug) return o;
    }
    return null;
  }

  Future<DisputeModel?> fetchDispute(String orderSlug) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _disputes[orderSlug];
  }
}
