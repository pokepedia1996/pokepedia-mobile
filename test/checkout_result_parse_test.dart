import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';

/// The reply is read after the money moved, so a malformed amount must read
/// as absent instead of throwing and stranding the buyer mid-checkout.
void main() {
  CheckoutResult parse(Object? koin) => CheckoutGateway.resultFromJson({
    'ok': true,
    'externalId': 'INV-1',
    'invoiceUrl': 'https://x',
    'totalAmount': 300000,
    'koinAmount': koin,
  });

  test('a number is read as is', () {
    expect(parse(50000).koinAmount, 50000);
    expect(parse(50000.4).koinAmount, 50000);
  });

  test('a numeric string (Postgres numeric) is read', () {
    expect(parse('50000').koinAmount, 50000);
  });

  test('null, junk or a negative amount reads as absent', () {
    expect(parse(null).koinAmount, isNull);
    expect(parse('abc').koinAmount, isNull);
    expect(parse(-1).koinAmount, isNull);
    expect(parse(<String, dynamic>{}).koinAmount, isNull);
  });

  test('the rest of the reply still parses', () {
    final r = parse('oops');
    expect(r.externalId, 'INV-1');
    expect(r.totalAmount, 300000);
  });
}
