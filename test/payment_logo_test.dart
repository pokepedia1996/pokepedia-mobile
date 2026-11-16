import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/presentation/checkout/payment_method_picker.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';

void main() {
  test('every logo the picker names is in the app', () {
    for (final channel in PaymentChannel.values) {
      final asset = paymentLogoAsset(channel);
      if (asset != null) {
        expect(File(asset).existsSync(), isTrue, reason: '$channel: $asset');
      }
    }
  });

  test('web has logos for QRIS and six banks; the rest fall back', () {
    expect(
      paymentLogoAsset(PaymentChannel.qris),
      'assets/images/payment/qris.webp',
    );
    expect(
      paymentLogoAsset(PaymentChannel.bca),
      'assets/images/payment/bca.webp',
    );
    expect(paymentLogoAsset(PaymentChannel.sinarmas), isNull);
  });

  Future<void> pump(WidgetTester tester, PaymentChannel channel) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentLogo(channel: channel, fallback: Icons.credit_card),
          ),
        ),
      );

  testWidgets('shows the bank logo', (tester) async {
    await pump(tester, PaymentChannel.mandiri);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows the icon for a bank without a logo', (tester) async {
    await pump(tester, PaymentChannel.danamon);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.credit_card), findsOneWidget);
  });
}
