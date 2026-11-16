import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/presentation/payment_webview_page.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_pricing.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';

void main() {
  group('PaymentOptions.fromJson', () {
    final doku = PaymentOptions.fromJson({
      'gateway': 'doku',
      'channels': [
        {'channel': 'BCA', 'minIdr': 0, 'maxIdr': null},
        {'channel': 'SINARMAS', 'minIdr': 0, 'maxIdr': null},
        {'channel': 'GOPAY', 'minIdr': 0, 'maxIdr': null},
      ],
    });

    test('reads the gateway and its rules, in order', () {
      expect(doku.gateway, 'doku');
      expect(doku.fromServer, isTrue);
      expect(availablePaymentChannels(10000, doku), [
        PaymentChannel.bca,
        PaymentChannel.sinarmas,
      ]);
    });

    test('leaves out a channel this version does not know', () {
      expect(doku.offered, {PaymentChannel.bca, PaymentChannel.sinarmas});
    });

    test('keeps QRIS and VA apart by total while QRIS is on', () {
      final options = PaymentOptions.fromJson({
        'gateway': 'doku',
        'channels': [
          {'channel': 'QRIS', 'minIdr': 0, 'maxIdr': 1449999},
          {'channel': 'BRI', 'minIdr': 1450000, 'maxIdr': null},
        ],
      });
      expect(availablePaymentChannels(1449999, options), [PaymentChannel.qris]);
      expect(availablePaymentChannels(1450000, options), [PaymentChannel.bri]);
      expect(options.maxIdrFor(PaymentChannelGroup.qr), 1449999);
      expect(options.minIdrFor(PaymentChannelGroup.va), 1450000);
    });
  });

  test('the default is Xendit, and is not the server speaking', () {
    expect(PaymentOptions.xenditDefault.gateway, 'xendit');
    expect(PaymentOptions.xenditDefault.fromServer, isFalse);
  });

  test('autoSelectPayment picks from the server rules', () {
    final options = PaymentOptions.fromJson({
      'gateway': 'doku',
      'channels': [
        {'channel': 'BCA', 'minIdr': 0, 'maxIdr': null},
      ],
    });
    final pick = autoSelectPayment(
      grandTotalIdr: 50000,
      walletBalance: 0,
      options: options,
    );
    expect(pick.channel, PaymentChannel.bca);

    final none = autoSelectPayment(
      grandTotalIdr: 50000,
      walletBalance: 0,
      options: const PaymentOptions(gateway: 'doku', rules: []),
    );
    expect(none.channel, isNull);
  });

  group('checkoutRequestBody', () {
    Map<String, dynamic> body({required bool sendGateways}) =>
        CheckoutGateway.checkoutRequestBody(
          courierChoices: const [],
          deliveryAddressSlug: 'home',
          paymentMethod: PaymentMethod.xendit,
          paymentChannel: PaymentChannel.danamon,
          sendGateways: sendGateways,
        );

    test('says which gateways the app can open once it has the rules', () {
      final sent = body(sendGateways: true);
      expect(sent['client'], 'app');
      expect(sent['paymentGateways'], ['xendit', 'doku']);
      expect(sent['paymentChannel'], 'DANAMON');
    });

    test('says nothing on the Xendit default', () {
      final sent = body(sendGateways: false);
      expect(sent.containsKey('paymentGateways'), isFalse);
      expect(sent.containsKey('client'), isFalse);
    });
  });

  test('PaymentWebViewPage stays on the gateway hosts', () {
    bool ok(String url) =>
        PaymentWebViewPage.isGatewayNavigation(Uri.parse(url));
    expect(ok('https://checkout.xendit.co/web/abc'), isTrue);
    expect(ok('https://staging.doku.com/checkout-link-v2/abc'), isTrue);
    expect(ok('https://jokul.doku.com/checkout/abc'), isTrue);
    expect(ok('https://app-sandbox.doku.com/x'), isTrue);
    expect(ok('http://staging.doku.com/x'), isFalse);
    expect(ok('https://evil-doku.com/x'), isFalse);
    expect(ok('https://pokepedia.id/orders'), isFalse);
  });
}
