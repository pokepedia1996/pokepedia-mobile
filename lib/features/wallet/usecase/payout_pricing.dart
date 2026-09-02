/// The withdrawal arithmetic the saldo screen shows before you commit to a
/// payout, ported from web so the two clients quote the same numbers:
/// `MIN_WITHDRAWAL` (`lib/utils/constants.ts`), `estimateXenditPayoutFee`
/// (`lib/payments/pricing.ts`) and `describePayoutSpeed`
/// (`features/wallet/server/payout-speed.ts`).
///
/// Estimates only — the server recomputes the fee when the payout is
/// created, and it is the number that actually leaves the balance.
library;

/// The smallest amount that may land in a seller's bank, before the fee is
/// added on top.
const kMinWithdrawal = 10000;

const _xenditPayoutFeeBankFlat = 2500;
const _xenditPayoutFeeEwalletFlat = 2500;
const _xenditFeePpnPct = 11;

/// The e-wallet payout channels, which Xendit prices separately from banks.
const _ewalletChannelCodes = {
  'ID_OVO',
  'ID_DANA',
  'ID_SHOPEEPAY',
  'ID_LINKAJA',
};

int _applyPpn(int baseFee) =>
    ((baseFee * (100 + _xenditFeePpnPct)) / 100).ceil();

/// Xendit's flat payout fee for [bankCode], PPN included.
int estimateXenditPayoutFee(String? bankCode) {
  final code = (bankCode ?? '').toUpperCase();
  final base = _ewalletChannelCodes.contains(code)
      ? _xenditPayoutFeeEwalletFlat
      : _xenditPayoutFeeBankFlat;
  return _applyPpn(base);
}

class PayoutSpeed {
  const PayoutSpeed({
    required this.eta,
    required this.cutoffPassed,
    required this.isWeekend,
  });

  final String eta;
  final bool cutoffPassed;
  final bool isWeekend;
}

const _wibOffsetMinutes = 7 * 60;

/// Xendit's daily disbursement cutoff, 14:30 WIB.
const _cutoffMinutes = 14 * 60 + 30;

/// When the money should land, given [now]. Read in WIB regardless of the
/// phone's own timezone — the cutoff belongs to the bank rails, not to the
/// person watching the clock.
PayoutSpeed describePayoutSpeed(DateTime now) {
  final utc = now.toUtc();
  final utcMinutes = utc.hour * 60 + utc.minute;
  final minutesOfDay = (utcMinutes + _wibOffsetMinutes) % (24 * 60);
  final dayShift = (utcMinutes + _wibOffsetMinutes) ~/ (24 * 60);
  // DateTime.weekday is 1=Monday..7=Sunday; the port's arithmetic is in
  // 0=Sunday..6=Saturday, as JavaScript's getUTCDay returns.
  final dow = (utc.weekday % 7 + dayShift) % 7;

  final isWeekend = dow == 0 || dow == 6;
  final cutoffPassed = minutesOfDay >= _cutoffMinutes;

  if (!isWeekend && !cutoffPassed) {
    return const PayoutSpeed(
      eta: 'Diterima hari ini, biasanya sebelum 17:00 WIB',
      cutoffPassed: false,
      isWeekend: false,
    );
  }
  if (isWeekend) {
    return PayoutSpeed(
      eta: 'Diterima hari kerja berikutnya (Senin pagi)',
      cutoffPassed: cutoffPassed,
      isWeekend: true,
    );
  }
  return const PayoutSpeed(
    eta: 'Diterima besok pagi (hari kerja)',
    cutoffPassed: true,
    isWeekend: false,
  );
}
