import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/order_model.dart';
import '../../repository/models/seller_order.dart';

/// `BITESHIP_STATUS_LABEL` — the courier's own vocabulary, in Indonesian.
const _statusLabel = <String, String>{
  'confirmed': 'Pesanan dibuat',
  'scheduled': 'Pickup dijadwalkan',
  'allocated': 'Driver dialokasikan',
  'picking_up': 'Driver menjemput',
  'picked': 'Kartu sudah dijemput',
  'in_transit': 'Dalam perjalanan antar hub',
  'dropping_off': 'Driver dalam perjalanan',
  'delivered': 'Paket sampai ke pembeli',
  'cancelled': 'Dibatalkan',
  'rejected': 'Ditolak kurir',
  'courier_not_found': 'Kurir tidak tersedia',
  'driver_not_found': 'Driver tidak ditemukan',
  'on_hold': 'Tertahan',
  'problem': 'Bermasalah',
  'failed_pickup': 'Pickup gagal',
  'delivery_exception': 'Pengiriman terganggu',
  'return_in_transit': 'Diretur',
  'returned': 'Dikembalikan',
  'disposed': 'Dihancurkan kurir',
};

String biteshipStatusLabel(String? status) =>
    status == null ? '-' : (_statusLabel[status] ?? status);

/// `TERMINAL_DANGER` / `TERMINAL_WARNING` — steps that ended badly, coloured
/// regardless of whether they're the latest.
const _danger = {'cancelled', 'rejected', 'courier_not_found', 'disposed'};
const _warning = {'on_hold', 'return_in_transit', 'returned'};

/// Ports `BiteshipTrackingTimeline` — the courier's trail, newest first.
///
/// The section used to be a resi line and nothing else, so a buyer could see
/// the number but never where the parcel had got to.
class TrackingTimeline extends StatelessWidget {
  const TrackingTimeline({super.key, required this.order});

  final OrderModel order;

  /// Ports `normalizeHistory`: drop entries missing a status or a time,
  /// de-duplicate on the pair, and sort newest first.
  List<ShipmentStatusEntry> get _entries {
    final seen = <String>{};
    final unique = <ShipmentStatusEntry>[];
    for (final entry in order.statusHistory ?? const <ShipmentStatusEntry>[]) {
      final status = entry.status;
      final at = entry.at;
      if (status == null || at == null) continue;
      if (!seen.add('$status|${at.toIso8601String()}')) continue;
      unique.add(entry);
    }
    unique.sort((a, b) => b.at!.compareTo(a.at!));
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    if (entries.isEmpty) {
      // The untrackable case never reaches here: the caller swaps this
      // widget out for the courier notice, as web does.
      return Text(
        'Belum ada pembaruan dari kurir.',
        style: AppTypography.bodySm(context.mutedForeground),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          _Step(
            entry: entries[i],
            isLatest: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.entry,
    required this.isLatest,
    required this.isLast,
  });

  final ShipmentStatusEntry entry;
  final bool isLatest;
  final bool isLast;

  /// Ports `toneFor`.
  Color _tone(BuildContext context) {
    final status = entry.status;
    if (status == 'delivered') return context.appSemantic.success;
    if (_danger.contains(status)) return context.appColors.error;
    if (_warning.contains(status)) return context.appSemantic.condMp;
    return isLatest ? context.appColors.primary : context.mutedForeground;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tone = _tone(context);
    final at = entry.at;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rail: a dot per step, joined by a line except after the last.
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isLatest || tone != context.mutedForeground
                      ? tone
                      : tone.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: context.borderColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    biteshipStatusLabel(entry.status),
                    style: isLatest
                        ? AppTypography.bodySmSemibold(colors.onSurface)
                        : AppTypography.bodySm(colors.onSurface),
                  ),
                  if (at != null)
                    Text(
                      '${formatShortDateId(at)} · ${formatClockId(at)}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  if (entry.note?.isNotEmpty ?? false)
                    Text(
                      entry.note!,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
