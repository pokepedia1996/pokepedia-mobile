import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../usecase/proposals_notifier.dart';

/// Opens the "Buat Penawaran" form for an ask listing. Resolves true once
/// an offer was submitted.
Future<bool?> showMakeOfferSheet(
  BuildContext context, {
  required ListingModel listing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _MakeOfferSheet(listing: listing),
  );
}

/// Ports the buyer half of `features/offer` — a price and quantity against
/// a seller's ask, submitted through the `submit_offer` RPC that
/// `POST /api/listing-offers` wraps on the web.
class _MakeOfferSheet extends ConsumerStatefulWidget {
  const _MakeOfferSheet({required this.listing});

  final ListingModel listing;

  @override
  ConsumerState<_MakeOfferSheet> createState() => _MakeOfferSheetState();
}

class _MakeOfferSheetState extends ConsumerState<_MakeOfferSheet> {
  late final TextEditingController _price;
  final _message = TextEditingController();
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Seeded a notch under the asking price, like the web form.
    final suggested = (widget.listing.price * 0.9).round();
    _price = TextEditingController(text: '$suggested');
  }

  @override
  void dispose() {
    _price.dispose();
    _message.dispose();
    super.dispose();
  }

  int get _priceValue =>
      int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _submit() async {
    if (_priceValue <= 0) {
      setState(() => _error = 'Masukkan harga penawaran.');
      return;
    }
    if (_priceValue >= widget.listing.price) {
      setState(() => _error = 'Penawaran harus di bawah harga listing.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await ref
        .read(proposalsRepositoryProvider)
        .submitOffer(
          askSlug: widget.listing.slug,
          quantity: _quantity,
          price: _priceValue,
          message: _message.text.trim().isEmpty ? null : _message.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.invalidate(myOffersProvider);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Penawaran terkirim'),
          duration: const Duration(seconds: 3),
          // Without this a SnackBar carrying an action never times out.
          persist: false,
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => context.push(Routes.proposals),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final listing = widget.listing;
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final maxQuantity = listing.available < 1 ? 1 : listing.available;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Buat Penawaran',
                  style: AppTypography.h3(colors.onSurface),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ],
          ),
          Text(
            '${listing.card.name} · ${listing.condition.short} · '
            '${listing.storeName}',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 4),
          Text(
            'Harga listing ${formatRupiah(listing.price)}',
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
          const SizedBox(height: 16),
          if (!signedIn)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.login);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Masuk untuk menawar'),
            )
          else ...[
            Text(
              'Harga penawaran',
              style: AppTypography.captionSemibold(context.mutedForeground),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixText: 'Rp ',
                hintText: '0',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Jumlah',
                  style: AppTypography.captionSemibold(context.mutedForeground),
                ),
                const Spacer(),
                QuantitySelector(
                  value: _quantity,
                  min: 1,
                  max: maxQuantity,
                  onChanged: (value) => setState(() => _quantity = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              // `submit_offer` refuses past 280 with `message_too_long`.
              maxLength: 280,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Pesan untuk penjual (opsional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: AppTypography.bodySm(colors.error)),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.appSemantic.success,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Tawar ${formatRupiah(_priceValue)}'),
            ),
          ],
        ],
      ),
    );
  }
}
