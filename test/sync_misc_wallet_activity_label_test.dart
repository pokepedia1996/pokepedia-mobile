import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/wallet/repository/models/wallet_models.dart';
import 'package:pokepedia_mobile/features/wallet/utils/activity_label.dart';

ActivityContext row(
  String reason, {
  String? notes,
  String? counterpartyUsername,
  int? counterpartyCount,
  List<String>? itemNames,
  int? itemCount,
}) => (
  reason: reason,
  notes: notes,
  counterpartyUsername: counterpartyUsername,
  counterpartyCount: counterpartyCount,
  itemNames: itemNames,
  itemCount: itemCount,
);

void main() {
  group('describeActivity (web activity-label.test.ts)', () {
    test('names the seller and items of a wallet checkout', () {
      expect(
        describeActivity(
          row(
            'checkout_payment',
            notes: 'checkout-123',
            counterpartyUsername: 'alice',
            counterpartyCount: 1,
            itemNames: ['Pikachu', 'Charizard ex'],
            itemCount: 2,
          ),
        ),
        (title: 'Pembayaran ke @alice', detail: 'Pikachu, Charizard ex'),
      );
    });

    test('summarises a multi-seller checkout and items beyond the first', () {
      expect(
        describeActivity(
          row(
            'checkout_payment',
            counterpartyUsername: 'alice',
            counterpartyCount: 3,
            itemNames: ['A', 'B', 'C'],
            itemCount: 5,
          ),
        ),
        (
          title: 'Pembayaran ke @alice dan 2 penjual lain',
          detail: 'A, B, C +2 lainnya',
        ),
      );
    });

    test('says who a refund came from and for which card', () {
      expect(
        describeActivity(
          row(
            'buyer_cancel_refund',
            counterpartyUsername: 'bob',
            counterpartyCount: 1,
            itemNames: ['Mewtwo'],
            itemCount: 1,
          ),
        ),
        (title: 'Refund dari @bob', detail: 'Mewtwo · Pembatalan pesanan'),
      );
    });

    test('a seller partial refund comes from the seller', () {
      expect(describeActivity(row('seller_partial_refund')), (
        title: 'Refund sebagian dari penjual',
        detail: 'Refund sebagian',
      ));
    });

    test('names the buyer on an escrow release', () {
      expect(
        describeActivity(
          row(
            'escrow_release',
            counterpartyUsername: 'carol',
            itemNames: ['Eevee'],
            itemCount: 1,
          ),
        ),
        (title: 'Pencairan saldo pesanan', detail: 'Eevee · Pembeli @carol'),
      );
    });

    test('falls back without leaking the raw reason or cart note', () {
      expect(describeActivity(row('checkout_payment', notes: 'checkout-123')), (
        title: 'Pembayaran pesanan',
        detail: null,
      ));
      expect(describeActivity(row('lost_package_refund')), (
        title: 'Refund paket hilang',
        detail: 'Paket hilang',
      ));
      expect(describeActivity(row('something_new')).title, 'Transaksi saldo');
    });

    test('keeps withdrawal notes as the detail line', () {
      expect(
        describeActivity(row('withdrawal_reverse', notes: 'Payout reversed')),
        (title: 'Penarikan dibatalkan', detail: 'Payout reversed'),
      );
    });
  });

  test('WalletActivity.fromRow reads the counterparty fields', () {
    final activity = WalletActivity.fromRow({
      'id': 7,
      'reason': 'lost_package_refund',
      'amount': 50000,
      'balance_after': 120000,
      'notes': null,
      'created_at': '2026-10-05T10:00:00Z',
      'counterparty_username': 'dave',
      'counterparty_count': 1,
      'item_names': ['Mew', 'Lugia', 'Ho-Oh'],
      'item_count': 4,
    });
    expect(activity.isCredit, isTrue);
    expect(activity.description, (
      title: 'Refund dari @dave',
      detail: 'Mew, Lugia, Ho-Oh +1 lainnya · Paket hilang',
    ));
  });

  test('WalletActivity.fromRow tolerates rows without the new fields', () {
    final activity = WalletActivity.fromRow({
      'id': 8,
      'reason': 'withdrawal_debit',
      'amount': -10000,
      'balance_after': 0,
      'notes': 'BCA •••1234',
      'created_at': '2026-10-05T10:00:00Z',
    });
    expect(activity.description, (
      title: 'Penarikan ke rekening',
      detail: 'BCA •••1234',
    ));
  });
}
