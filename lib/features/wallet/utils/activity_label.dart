/// What one activity row reads as — web's `ActivityDescription` in
/// `features/wallet/utils/activity-label.ts`.
typedef ActivityDescription = ({String title, String? detail});

/// The `get_wallet_activity` fields the label is built from — web's
/// `ActivityContext`.
typedef ActivityContext = ({
  String reason,
  String? notes,
  String? counterpartyUsername,
  int? counterpartyCount,
  List<String>? itemNames,
  int? itemCount,
});

/// Web's `GENERIC_TITLE`.
const _genericTitle = <String, String>{
  'checkout_payment': 'Pembayaran pesanan',
  'escrow_release': 'Pencairan saldo pesanan',
  'dispute_release_seller': 'Dana dirilis dari laporan',
  'dispute_partial_release': 'Dana parsial dari laporan',
  'buyer_cancel_refund': 'Refund pembatalan pesanan',
  'courier_cancel_refund': 'Refund kurir membatalkan pengiriman',
  'dispute_refund_buyer': 'Refund hasil laporan',
  'dispute_partial_refund': 'Refund parsial hasil laporan',
  'seller_partial_refund': 'Refund sebagian dari penjual',
  'lost_package_refund': 'Refund paket hilang',
  'withdrawal_debit': 'Penarikan ke rekening',
  'withdrawal_reverse': 'Penarikan dibatalkan',
};

const _fallbackTitle = 'Transaksi saldo';

/// Web's `REFUND_CAUSE`.
const _refundCause = <String, String>{
  'buyer_cancel_refund': 'Pembatalan pesanan',
  'courier_cancel_refund': 'Kurir membatalkan pengiriman',
  'dispute_refund_buyer': 'Hasil laporan',
  'dispute_partial_refund': 'Refund parsial hasil laporan',
  'seller_partial_refund': 'Refund sebagian',
  'lost_package_refund': 'Paket hilang',
};

/// Web's `EARNING_REASONS`.
const _earningReasons = {
  'escrow_release',
  'dispute_release_seller',
  'dispute_partial_release',
};

String _titleFor(String reason) => _genericTitle[reason] ?? _fallbackTitle;

String? _describeItems(ActivityContext row) {
  final names = row.itemNames ?? const <String>[];
  if (names.isEmpty) return null;
  final hiddenCount = (row.itemCount ?? names.length) - names.length;
  final listed = names.join(', ');
  return hiddenCount > 0 ? '$listed +$hiddenCount lainnya' : listed;
}

String _describeSellers(String username, int sellerCount) {
  final otherSellers = sellerCount - 1;
  return otherSellers > 0
      ? '@$username dan $otherSellers penjual lain'
      : '@$username';
}

String? _joinParts(List<String?> parts) {
  final present = [
    for (final part in parts)
      if (part != null && part.isNotEmpty) part,
  ];
  return present.isEmpty ? null : present.join(' · ');
}

/// Ports web's `describeActivity`: who the money went to or came from and
/// for which cards, falling back to a generic title so neither the raw
/// reason code nor a cart note ever reaches the feed.
ActivityDescription describeActivity(ActivityContext row) {
  final counterparty = row.counterpartyUsername;
  final items = _describeItems(row);

  if (row.reason == 'checkout_payment') {
    return (
      title: counterparty != null
          ? 'Pembayaran ke '
                '${_describeSellers(counterparty, row.counterpartyCount ?? 1)}'
          : _titleFor(row.reason),
      detail: items,
    );
  }

  final refundCause = _refundCause[row.reason];
  if (refundCause != null) {
    return (
      title: counterparty != null
          ? 'Refund dari @$counterparty'
          : _titleFor(row.reason),
      detail: _joinParts([items, refundCause]),
    );
  }

  if (_earningReasons.contains(row.reason)) {
    return (
      title: _titleFor(row.reason),
      detail: _joinParts([
        items,
        counterparty != null ? 'Pembeli @$counterparty' : null,
      ]),
    );
  }

  return (title: _titleFor(row.reason), detail: row.notes);
}
