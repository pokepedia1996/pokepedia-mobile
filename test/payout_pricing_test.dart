import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/wallet/repository/models/wallet_models.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/payout_pricing.dart';

/// The saldo screen quotes a fee and a cutoff before the server ever sees the
/// request, so these have to agree with `lib/payments/pricing.ts` and
/// `features/wallet/server/payout-speed.ts` on web. Wrong here means a seller
/// is quoted one number and charged another.
void main() {
  group('estimateXenditPayoutFee', () {
    test('is the flat bank fee plus 11% PPN', () {
      expect(estimateXenditPayoutFee('ID_BCA'), 2775);
    });

    test('prices e-wallet channels the same as banks today', () {
      expect(estimateXenditPayoutFee('ID_OVO'), 2775);
      expect(estimateXenditPayoutFee('ID_DANA'), 2775);
    });

    test('falls back to the bank fee for an unknown or missing channel', () {
      expect(estimateXenditPayoutFee(null), 2775);
      expect(estimateXenditPayoutFee('SOMETHING_ELSE'), 2775);
    });
  });

  group('describePayoutSpeed', () {
    // 2026-09-02 is a Wednesday. WIB is UTC+7.
    test('before the 14:30 WIB cutoff on a weekday lands same day', () {
      final speed = describePayoutSpeed(DateTime.utc(2026, 9, 2, 3));
      expect(speed.cutoffPassed, isFalse);
      expect(speed.isWeekend, isFalse);
      expect(speed.eta, contains('hari ini'));
    });

    test('after the cutoff lands the next morning', () {
      // 08:00 UTC is 15:00 WIB, past the cutoff.
      final speed = describePayoutSpeed(DateTime.utc(2026, 9, 2, 8));
      expect(speed.cutoffPassed, isTrue);
      expect(speed.eta, contains('besok pagi'));
    });

    test('reads the weekend in WIB, not in UTC', () {
      // Friday 18:00 UTC is already Saturday 01:00 WIB.
      final speed = describePayoutSpeed(DateTime.utc(2026, 9, 4, 18));
      expect(speed.isWeekend, isTrue);
      expect(speed.eta, contains('Senin'));
    });
  });

  group('destination formatting', () {
    test('masks all but the last four digits', () {
      expect(maskAccount('1234567890'), '•••7890');
      expect(maskAccount('123'), '123');
    });

    test('names known banks and strips the ID_ prefix from the rest', () {
      expect(bankLabel('ID_BCA'), 'BCA');
      expect(bankLabel('ID_SOMETHING'), 'SOMETHING');
    });

    test('leads with the nickname when one was given', () {
      const withNickname = WithdrawalDestination(
        id: 1,
        bankCode: 'ID_BCA',
        accountNumber: '1234567890',
        accountHolderName: 'Budi',
        nickname: 'Tabungan utama',
        isDefault: true,
      );
      expect(withNickname.title, 'Tabungan utama');
      expect(withNickname.copyWithoutNickname().title, 'BCA');
    });
  });
}

extension on WithdrawalDestination {
  WithdrawalDestination copyWithoutNickname() => WithdrawalDestination(
    id: id,
    bankCode: bankCode,
    accountNumber: accountNumber,
    accountHolderName: accountHolderName,
    nickname: null,
    isDefault: isDefault,
  );
}
