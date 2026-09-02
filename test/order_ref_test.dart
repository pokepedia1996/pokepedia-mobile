import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_ref.dart';

/// A notification's `action_url` names an order in one of two shapes, and the
/// repository picks which column to filter on from this. Getting it wrong is
/// not a miss but a Postgres error — a uuid column compared to `ord-…` raises
/// 22P02 — which surfaces as "Gagal memuat pesanan" on a tapped notification.
void main() {
  test('a uuid is a slug', () {
    expect(
      classifyOrderRef('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'),
      OrderRefKind.slug,
    );
    // Postgres prints uuids lowercase; a link may still carry them uppercased.
    expect(
      classifyOrderRef('A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11'),
      OrderRefKind.slug,
    );
  });

  test('an order number is recognised in the shape the generators mint', () {
    expect(classifyOrderRef('ord-260901-a7k3p'), OrderRefKind.orderNumber);
    // Both `generate_order_number` and `generate_package_order_number` store
    // lowercase, but a link that shouted it should still resolve.
    expect(classifyOrderRef('ORD-260901-A7K3P'), OrderRefKind.orderNumber);
    expect(classifyOrderRef(' ord-260901-a7k3p '), OrderRefKind.orderNumber);
  });

  test('anything else is refused rather than sent to Postgres', () {
    expect(classifyOrderRef(''), OrderRefKind.unknown);
    expect(classifyOrderRef('12345'), OrderRefKind.unknown);
    expect(classifyOrderRef('ord-26091-a7k3p'), OrderRefKind.unknown);
    expect(classifyOrderRef('ord-260901-a7k3'), OrderRefKind.unknown);
    expect(classifyOrderRef('not-a-uuid-at-all'), OrderRefKind.unknown);
    expect(
      classifyOrderRef("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' OR 1=1"),
      OrderRefKind.unknown,
    );
  });
}
