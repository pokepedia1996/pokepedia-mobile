import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/presentation/checkout_status_page.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';

/// A payment whose notification never arrives: the row stays pending, and
/// only the gateway check could settle it.
class _Gateway implements CheckoutGateway {
  _Gateway({this.syncFails = false});

  final bool syncFails;
  final syncedAt = <int>[];
  int reads = 0;

  @override
  Future<void> syncPayment(String externalId) async {
    syncedAt.add(reads + 1);
    if (syncFails) throw Exception('gateway lookup failed');
  }

  @override
  Future<CheckoutProgress> fetchProgress(String externalId) async {
    reads++;
    return const CheckoutProgress(
      status: CheckoutStatus.pending,
      raw: 'pending',
    );
  }

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

Future<void> _waitOut(WidgetTester tester, _Gateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [checkoutGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: CheckoutStatusPage(externalId: 'INV-1')),
    ),
  );
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(seconds: 2));
  }
}

void main() {
  test('asks the gateway from about six seconds in, then every ten', () {
    final asks = [
      for (var attempt = 1; attempt <= 30; attempt++)
        if (CheckoutStatusPage.asksGateway(attempt)) attempt,
    ];
    expect(asks, [3, 8, 13, 18, 23, 28]);
  });

  testWidgets('has the server check with the gateway while waiting', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _waitOut(tester, gateway);
    expect(gateway.syncedAt, [3, 8, 13, 18, 23, 28]);
    expect(gateway.reads, 30);
  });

  testWidgets('a failed gateway check does not stop the waiting', (
    tester,
  ) async {
    final gateway = _Gateway(syncFails: true);
    await _waitOut(tester, gateway);
    expect(gateway.syncedAt, hasLength(6));
    expect(gateway.reads, 30);
  });
}
