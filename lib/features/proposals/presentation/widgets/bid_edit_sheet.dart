import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/my_bid.dart';

/// What the seller changed. Null fields are left alone, which is what
/// `update_order_self` expects — it rejects a call where everything is null
/// with `nothing_to_update`.
class BidEdit {
  const BidEdit({this.price, this.quantity});

  final int? price;
  final int? quantity;

  bool get isEmpty => price == null && quantity == null;
}

/// Ports `BuyerBidsList`'s edit modal — price and quantity on one bid.
Future<BidEdit?> showBidEditSheet(
  BuildContext context, {
  required MyBidModel bid,
}) {
  return showModalBottomSheet<BidEdit>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _BidEditSheet(bid: bid),
  );
}

class _BidEditSheet extends StatefulWidget {
  const _BidEditSheet({required this.bid});

  final MyBidModel bid;

  @override
  State<_BidEditSheet> createState() => _BidEditSheetState();
}

class _BidEditSheetState extends State<_BidEditSheet> {
  late final _price = TextEditingController(text: widget.bid.price.toString());
  late int _quantity = widget.bid.quantity;
  String? _error;

  /// `update_order_self` caps quantity at 99 and refuses anything below what
  /// a buyer already has locked.
  int get _minQuantity => widget.bid.qtyLocked.clamp(1, 99);

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final price = int.tryParse(_price.text.trim().replaceAll('.', ''));
    if (price == null || price <= 0 || price > 999999999) {
      setState(() => _error = 'Harga tidak valid.');
      return;
    }

    final edit = BidEdit(
      // Only what actually changed: the RPC treats null as "leave it".
      price: price == widget.bid.price ? null : price,
      quantity: _quantity == widget.bid.quantity ? null : _quantity,
    );
    if (edit.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(edit);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Bid', style: AppTypography.h3(colors.onSurface)),
            const SizedBox(height: 2),
            Text(
              widget.bid.card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Harga per kartu',
                prefixText: 'Rp ',
                isDense: true,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Jumlah',
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: _quantity > _minQuantity
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(LucideIcons.circleMinus, size: 20),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: _quantity < 99
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(LucideIcons.circlePlus, size: 20),
                ),
              ],
            ),
            if (widget.bid.qtyLocked > 0)
              Text(
                '${widget.bid.qtyLocked} sudah terkunci dan tidak bisa '
                'dikurangi.',
                style: AppTypography.caption(context.mutedForeground),
              ),
            const SizedBox(height: 16),
            Text(
              'Total ${formatRupiah((int.tryParse(_price.text.trim()) ?? 0) * _quantity)}',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
