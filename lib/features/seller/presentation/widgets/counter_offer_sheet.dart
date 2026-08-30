import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/listing_offer.dart';

/// What the seller countered with.
class CounterOfferInput {
  const CounterOfferInput({required this.price, this.message});

  final int price;
  final String? message;
}

/// Ports `counter-offer-modal.tsx` for the seller's side.
///
/// The seller always counters *up*: the buyer asked for a discount, and the
/// reply is a smaller one. So the valid band is above the buyer's current
/// price and no higher than the listing price — the same rule the
/// `counter_offer` RPC enforces, checked here so a doomed price never
/// becomes a round trip.
Future<CounterOfferInput?> showCounterOfferSheet(
  BuildContext context, {
  required ListingOffer offer,
}) {
  return showModalBottomSheet<CounterOfferInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _CounterOfferSheet(offer: offer),
  );
}

class _CounterOfferSheet extends StatefulWidget {
  const _CounterOfferSheet({required this.offer});

  final ListingOffer offer;

  @override
  State<_CounterOfferSheet> createState() => _CounterOfferSheetState();
}

class _CounterOfferSheetState extends State<_CounterOfferSheet> {
  final _price = TextEditingController();
  final _message = TextEditingController();

  static const _maxMessageLength = 280;

  @override
  void dispose() {
    _price.dispose();
    _message.dispose();
    super.dispose();
  }

  int get _value =>
      int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  bool get _isValid =>
      _value > widget.offer.currentPrice && _value <= widget.offer.listingPrice;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final colors = context.appColors;
    final hint = _value > 0 && !_isValid
        ? 'Harus antara ${formatRupiah(offer.currentPrice + 1)} dan '
              '${formatRupiah(offer.listingPrice)}'
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tawar Balik',
                          style: AppTypography.h3(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ajukan harga lebih tinggi dari tawaran saat ini '
                          '(maks ${formatRupiah(offer.listingPrice)}).',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                'Tawaran pembeli saat ini ${formatRupiah(offer.currentPrice)}',
                style: AppTypography.caption(context.mutedForeground),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _price,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: '0',
                  errorText: hint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _message,
                maxLength: _maxMessageLength,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: 'Pesan untuk pembeli (opsional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              ElevatedButton(
                onPressed: _isValid
                    ? () => Navigator.of(context).pop(
                        CounterOfferInput(
                          price: _value,
                          message: _message.text,
                        ),
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Kirim Tawaran Balik'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
