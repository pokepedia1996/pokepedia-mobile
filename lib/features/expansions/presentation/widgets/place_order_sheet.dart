import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/condition_grade_picker.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../../cart/presentation/checkout_webview_page.dart';
import '../../repository/models/trading_models.dart';
import '../../usecase/trading_notifier.dart';

/// Opens the bid/ask form for [card]. Resolves true once an order was
/// actually placed, so the caller can refresh the book.
Future<bool?> showPlaceOrderSheet(
  BuildContext context, {
  required CardModel card,
  required String side,
  int? bestPrice,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) =>
        _PlaceOrderSheet(card: card, side: side, bestPrice: bestPrice),
  );
}

/// Ports `PlaceOrderModal` + the gating `OrderBookWidget` does around it:
/// sign-in, phone verification, and (for asks) an active seller profile
/// with couriers. The gates are read up front from
/// [tradeEligibilityProvider] so a blocked user sees why before filling
/// anything in, and are re-checked server-side by `place_order` regardless.
class _PlaceOrderSheet extends ConsumerStatefulWidget {
  const _PlaceOrderSheet({
    required this.card,
    required this.side,
    required this.bestPrice,
  });

  final CardModel card;
  final String side;
  final int? bestPrice;

  @override
  ConsumerState<_PlaceOrderSheet> createState() => _PlaceOrderSheetState();
}

class _PlaceOrderSheetState extends ConsumerState<_PlaceOrderSheet> {
  final _price = TextEditingController();
  CardCondition _condition = CardCondition.nm;
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  /// Photos of the actual copy being sold — `place_order` requires at least
  /// one on asks of Rp100.000 and up. Capped at 4, like the seller form.
  final List<File> _photos = [];

  bool get _isBid => widget.side == 'bid';

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _photos.add(File(picked.path)));
  }

  @override
  void initState() {
    super.initState();
    if (widget.bestPrice != null) {
      _price.text = widget.bestPrice.toString();
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  int get _priceValue =>
      int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _openWeb(String path) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CheckoutWebViewPage(path: path)),
    );
    if (!mounted) return;
    // The gate may have been cleared in the WebView — re-read it.
    ref.invalidate(tradeEligibilityProvider);
  }

  Future<void> _submit({bool replace = false}) async {
    final price = _priceValue;
    if (price <= 0) {
      setState(() => _error = 'Masukkan harga.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final repository = ref.read(tradingRepositoryProvider);

    // A bid that could buy outright is worth interrupting for — same check
    // the web runs before writing the order.
    if (_isBid && !replace) {
      final matches = await repository.fetchMatchingAsks(
        cardId: widget.card.id,
        price: price,
        condition: _condition,
      );
      if (!mounted) return;
      if (matches.isNotEmpty) {
        setState(() => _submitting = false);
        final proceed = await _showMatchingAsks(matches);
        if (proceed != true || !mounted) return;
        setState(() => _submitting = true);
      }
    }

    // Photos are uploaded first so `place_order` receives their URLs in the
    // same call the web route passes them in.
    var photoUrls = const <String>[];
    if (!_isBid && _photos.isNotEmpty) {
      try {
        photoUrls = await repository.uploadListingPhotos(_photos);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = 'Gagal mengunggah foto. Coba lagi.';
        });
        return;
      }
      if (!mounted) return;
    }

    final result = await repository.placeOrder(
      cardId: widget.card.id,
      side: widget.side,
      price: price,
      condition: _condition,
      quantity: _quantity,
      replace: replace,
      photoUrls: photoUrls,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result.status) {
      case PlaceOrderStatus.ok:
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _isBid ? 'Bid berhasil dipasang!' : 'Ask berhasil dipasang!',
              ),
            ),
          );
      case PlaceOrderStatus.duplicate:
        final replaceIt = await _confirmReplace(result.existingPrice ?? 0);
        if (replaceIt == true && mounted) await _submit(replace: true);
      case PlaceOrderStatus.failed:
        setState(() => _error = result.messageId);
    }
  }

  Future<bool?> _confirmReplace(int existingPrice) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Ganti order yang ada?'),
        content: Text(
          'Kamu sudah punya ${_isBid ? 'bid' : 'ask'} terbuka di '
          '${formatRupiah(existingPrice)} untuk kartu dan kondisi ini. '
          'Ganti dengan ${formatRupiah(_priceValue)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ganti'),
          ),
        ],
      ),
    );
  }

  /// Ports `MatchingAsksPopup` — the cheaper listings a bid could just buy.
  Future<bool?> _showMatchingAsks(List<MatchingAsk> asks) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bisa langsung dibeli',
              style: AppTypography.h3(context.appColors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Ada listing dengan kondisi yang sama di harga bid kamu atau '
              'lebih murah.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 14),
            for (final ask in asks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: ask.storeSlug.isEmpty
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop(false);
                          context.push(
                            Routes.storeCardDetail(ask.storeSlug, ask.cardId),
                          );
                        },
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formatRupiah(ask.price),
                                style: AppTypography.bodySemibold(
                                  context.appColors.onSurface,
                                ),
                              ),
                              Text(
                                '${ask.storeName} · ${ask.available} tersedia',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          LucideIcons.chevronRight,
                          color: context.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('Tetap pasang bid'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = ref.watch(authProvider).valueOrNull;
    final eligibility = ref.watch(tradeEligibilityProvider);

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
                  _isBid ? 'Pasang Bid (WTB)' : 'Pasang Ask (WTS)',
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
            '${widget.card.name} · ${widget.card.collectorNumber}',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 16),
          if (user == null)
            _Blocked(
              message: 'Masuk dulu untuk memasang order.',
              actionLabel: 'Masuk',
              onAction: () {
                Navigator.of(context).pop();
                context.push(Routes.login);
              },
            )
          else
            eligibility.when(
              data: (gates) => _form(gates),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const _Blocked(
                message: 'Gagal memeriksa status akun. Coba lagi.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(TradeEligibility gates) {
    final colors = context.appColors;

    if (!gates.phoneVerified) {
      return _Blocked(
        message:
            'Nomor HP kamu belum diverifikasi. Verifikasi wajib sebelum '
            'memasang order — prosesnya lewat WhatsApp di pokepedia.id.',
        actionLabel: 'Verifikasi sekarang',
        onAction: () => _openWeb('/settings'),
      );
    }
    if (_isBid && gates.biddingBanned) {
      return const _Blocked(
        message: 'Akun kamu sedang dibatasi untuk memasang bid.',
      );
    }
    if (!_isBid && !gates.sellerActive) {
      return _Blocked(
        message:
            'Ask hanya bisa dipasang oleh penjual aktif. Lengkapi profil '
            'penjual dulu di pokepedia.id.',
        actionLabel: 'Buka pengaturan penjual',
        onAction: () => _openWeb('/seller/settings'),
      );
    }
    if (!_isBid && !gates.hasCouriers) {
      return _Blocked(
        message: 'Pilih minimal satu kurir sebelum memasang ask.',
        actionLabel: 'Atur kurir',
        onAction: () => _openWeb('/seller/couriers'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Harga',
          style: AppTypography.captionSemibold(context.mutedForeground),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: 'Rp ',
            hintText: '0',
            helperText: widget.bestPrice == null
                ? null
                : _isBid
                ? 'Bid tertinggi saat ini ${formatRupiah(widget.bestPrice!)}'
                : 'Ask terendah saat ini ${formatRupiah(widget.bestPrice!)}',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Kondisi',
          style: AppTypography.captionSemibold(context.mutedForeground),
        ),
        const SizedBox(height: 6),
        ConditionGradePicker(
          value: _condition,
          showAllOption: false,
          onChanged: (value) =>
              setState(() => _condition = value ?? CardCondition.nm),
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
              max: 99,
              onChanged: (value) => setState(() => _quantity = value),
            ),
          ],
        ),
        if (!_isBid) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Foto kartu',
                style: AppTypography.captionSemibold(context.mutedForeground),
              ),
              const SizedBox(width: 6),
              if (_priceValue >= 100000)
                Text(
                  'wajib di atas Rp100.000',
                  style: AppTypography.caption(colors.error),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < _photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PhotoThumb(
                    file: _photos[i],
                    onRemove: () => setState(() => _photos.removeAt(i)),
                  ),
                ),
              if (_photos.length < 4)
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      LucideIcons.imagePlus,
                      size: 20,
                      color: context.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTypography.bodySm(colors.error)),
        ],
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _submitting || _priceValue <= 0 ? null : () => _submit(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isBid
                ? context.appSemantic.success
                : colors.error,
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
              : Text(_isBid ? 'Pasang Bid' : 'Pasang Ask'),
        ),
      ],
    );
  }
}

/// A gate the user can't pass in-app, with the web handoff that clears it.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.4),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// One picked photo, with the tap target that drops it again.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
