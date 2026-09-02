import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/listing_offer.dart';
import '../repository/offers_repository.dart';
import '../usecase/offers_notifier.dart';
import 'widgets/counter_offer_sheet.dart';
import 'widgets/reject_offer_sheet.dart';

/// Ports `/seller/products/offers/[slug]` — every offer a buyer has made on
/// one listing, and the three answers the seller can give.
///
/// Web splits the screen: buckets down the left, the chosen offer's detail on
/// the right. A phone has one column, so the buckets stay as collapsible
/// sections and tapping an offer opens its detail as a sheet — same
/// information, same order, one thing at a time.
class SellerListingOffersPage extends ConsumerStatefulWidget {
  const SellerListingOffersPage({super.key, required this.listingSlug});

  final String listingSlug;

  @override
  ConsumerState<SellerListingOffersPage> createState() =>
      _SellerListingOffersPageState();
}

class _SellerListingOffersPageState
    extends ConsumerState<SellerListingOffersPage> {
  /// Buckets the seller has opened. "Masuk" starts open because it is the
  /// one holding work; the rest are reference.
  final _open = <OfferBucket>{OfferBucket.received};

  /// Offers already reported as read, so a rebuild doesn't re-fire the RPC.
  final _seenDispatched = <String>{};

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(listingOffersProvider(widget.listingSlug));
    final offers = async.valueOrNull ?? const <ListingOffer>[];
    _markUnseen(offers);

    final grouped = <OfferBucket, List<ListingOffer>>{
      for (final bucket in OfferBucket.values) bucket: [],
    };
    for (final offer in offers) {
      grouped[offer.bucket]!.add(offer);
    }

    return Scaffold(
      appBar: TransparentAppBar(
        title: Text(
          'Penawaran',
          style: AppTypography.bodySemibold(colors.onSurface),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(receivedOffersProvider),
        child: async.isLoading && offers.isEmpty
            ? const Center(child: PikachuLoader())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (offers.isNotEmpty) ...[
                    _ListingHeader(offer: offers.first),
                    const SizedBox(height: 16),
                  ],

                  if (async.hasError)
                    const EmptyState(
                      icon: LucideIcons.circleAlert,
                      title: 'Gagal memuat penawaran',
                      description: 'Tarik ke bawah untuk mencoba lagi.',
                    )
                  else if (offers.isEmpty)
                    const EmptyState(
                      icon: LucideIcons.tag,
                      title: 'Belum ada penawaran',
                      description:
                          'Penawaran untuk listing ini akan muncul di sini.',
                    )
                  else
                    for (final bucket in OfferBucket.values) ...[
                      _BucketSection(
                        bucket: bucket,
                        offers: grouped[bucket]!,
                        expanded: _open.contains(bucket),
                        onToggle: () => setState(() {
                          if (!_open.remove(bucket)) _open.add(bucket);
                        }),
                        onSelect: _showOffer,
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
      ),
      backgroundColor: colors.surface,
    );
  }

  /// Clears the unread mark on anything the seller can now see, mirroring
  /// web's effect. Offers already reported are skipped so a rebuild — of
  /// which there are many — doesn't re-fire the RPC per offer.
  void _markUnseen(List<ListingOffer> offers) {
    final unseen = [
      for (final offer in offers)
        if (offer.status == OfferStatus.pending &&
            offer.seenAt == null &&
            !_seenDispatched.contains(offer.slug))
          offer.slug,
    ];
    if (unseen.isEmpty) return;

    _seenDispatched.addAll(unseen);
    final repository = ref.read(offersRepositoryProvider);
    for (final slug in unseen) {
      repository.markSeen(slug);
    }
  }

  Future<void> _showOffer(ListingOffer offer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _OfferDetailSheet(
        offer: offer,
        onAccept: () => _accept(offer),
        onCounter: () => _counter(offer),
        onReject: () => _reject(offer),
      ),
    );
  }

  Future<void> _accept(ListingOffer offer) async {
    if (_busy) return;
    await showConfirmDialog(
      context,
      title: 'Terima penawaran ini?',
      description:
          'Kamu akan menjual ${offer.quantity}x kartu seharga '
          '${formatRupiah(offer.currentPrice)} per pcs. Pembeli akan diminta '
          'membayar.',
      confirmLabel: 'Konfirmasi Terima',
      destructive: false,
      onConfirm: () => _run(
        () => ref.read(offersRepositoryProvider).accept(offer.slug),
        success: 'Penawaran diterima',
      ),
    );
  }

  Future<void> _counter(ListingOffer offer) async {
    final result = await showCounterOfferSheet(context, offer: offer);
    if (result == null) return;
    await _run(
      () => ref
          .read(offersRepositoryProvider)
          .counter(offer.slug, price: result.price, message: result.message),
      success: 'Tawaran balik terkirim',
    );
  }

  Future<void> _reject(ListingOffer offer) async {
    final note = await showRejectOfferSheet(context);
    if (note == null) return;
    await _run(
      () => ref
          .read(offersRepositoryProvider)
          .reject(offer.slug, note: note.value),
      success: 'Penawaran ditolak',
    );
  }

  /// Runs a mutation, then reloads. The reload is what closes the loop: the
  /// RPCs move the offer between buckets, and the screen is grouped by the
  /// very fields they change.
  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(receivedOffersProvider);
      _toast(success);
    } on OfferActionException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Gagal memproses penawaran');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }
}

/// The card being offered on, above the buckets — web's listing strip.
class _ListingHeader extends StatelessWidget {
  const _ListingHeader({required this.offer});

  final ListingOffer offer;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 67,
            child: CardArt(imageUrl: offer.cardImageUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.cardName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    offer.expansionCode,
                    offer.collectorNumber,
                    offer.variant,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  style: AppTypography.caption(context.mutedForeground),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Harga listing ',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                      TextSpan(
                        text: formatRupiah(offer.listingPrice),
                        style: AppTypography.captionSemibold(colors.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One collapsible bucket — web's left rail, stacked.
class _BucketSection extends StatelessWidget {
  const _BucketSection({
    required this.bucket,
    required this.offers,
    required this.expanded,
    required this.onToggle,
    required this.onSelect,
  });

  final OfferBucket bucket;
  final List<ListingOffer> offers;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ListingOffer> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Text(
                    bucket.label,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  if (offers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CountChip(count: offers.length),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 20,
                      color: context.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: offers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Text(
                        'Tidak ada penawaran.',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    )
                  : Column(
                      children: [
                        for (final offer in offers)
                          _OfferRow(offer: offer, onTap: () => onSelect(offer)),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: context.mutedForeground.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: AppTypography.badge(context.mutedForeground),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer, required this.onTap});

  final ListingOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _BuyerIdentity(offer: offer)),
                const SizedBox(width: 8),
                Text(
                  formatRupiah(offer.currentPrice),
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${offer.quantity}x · ${formatRelativeId(offer.createdAt)}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
                if (offer.needsSellerResponse)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      'Perlu dibalas',
                      style: AppTypography.badge(colors.primary),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerIdentity extends StatelessWidget {
  const _BuyerIdentity({required this.offer, this.size = 20});

  final ListingOffer offer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = offer.buyerUsername ?? 'Pembeli';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(imageUrl: offer.buyerAvatarUrl, username: name, size: size),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: size > 20
                ? AppTypography.captionSemibold(context.appColors.onSurface)
                : AppTypography.caption(context.mutedForeground),
          ),
        ),
      ],
    );
  }
}

/// Web's right-hand `OfferSummary`, as a sheet.
class _OfferDetailSheet extends StatefulWidget {
  const _OfferDetailSheet({
    required this.offer,
    required this.onAccept,
    required this.onCounter,
    required this.onReject,
  });

  final ListingOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onCounter;
  final VoidCallback onReject;

  @override
  State<_OfferDetailSheet> createState() => _OfferDetailSheetState();
}

class _OfferDetailSheetState extends State<_OfferDetailSheet> {
  bool _historyOpen = false;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final colors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _BuyerIdentity(offer: offer, size: 28)),
                  StatusPill(
                    label: offer.statusLabel,
                    color: _toneColor(context, offer),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  if (offer.priceDropped)
                    Text(
                      formatRupiah(offer.listingPrice),
                      style: AppTypography.caption(
                        context.mutedForeground,
                      ).copyWith(decoration: TextDecoration.lineThrough),
                    ),
                  Text(
                    formatRupiah(offer.currentPrice),
                    style: AppTypography.h3(colors.onSurface),
                  ),
                  Text(
                    '· ${offer.quantity}x · ${offer.condition.short}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),

              if (offer.status == OfferStatus.pending) ...[
                const SizedBox(height: 8),
                Text(
                  _countdown(offer.remaining),
                  style: AppTypography.caption(
                    offer.remaining.inHours < 6
                        ? colors.error
                        : context.mutedForeground,
                  ),
                ),
              ],

              const SizedBox(height: 12),
              // The buyer's city is deliberately absent: `user_addresses` is
              // readable only by its owner, so the app cannot resolve it the
              // way web's service client does. This is web's own fallback
              // copy rather than an empty box pretending otherwise.
              _InfoRow(
                icon: LucideIcons.mapPin,
                title: 'Tujuan pengiriman',
                body: 'Alamat dikonfirmasi saat checkout',
              ),

              if (offer.message != null && offer.message!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    border: Border(
                      left: BorderSide(color: context.borderColor, width: 2),
                    ),
                  ),
                  child: Text(
                    offer.message!,
                    style: AppTypography.bodySm(
                      colors.onSurface,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],

              if (offer.history.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _historyOpen = !_historyOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: _historyOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 16,
                            color: context.mutedForeground,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Riwayat negosiasi (${offer.history.length})',
                          style: AppTypography.captionSemibold(
                            context.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_historyOpen)
                  for (final entry in offer.history) _HistoryLine(entry: entry),
              ],

              if (offer.waitingOnBuyer) ...[
                const SizedBox(height: 12),
                Text(
                  'Menunggu respons pembeli',
                  style: AppTypography.captionSemibold(context.mutedForeground),
                ),
              ],

              if (offer.paymentState != null) ...[
                const SizedBox(height: 12),
                Text(switch (offer.paymentState!) {
                  OfferPaymentState.awaiting => 'Menunggu pembayaran pembeli',
                  OfferPaymentState.paid => 'Pembeli sudah membayar',
                  OfferPaymentState.cancelled => 'Pesanan dibatalkan',
                  OfferPaymentState.expired => 'Waktu bayar habis',
                }, style: AppTypography.caption(context.mutedForeground)),
              ],

              if (offer.needsSellerResponse) ...[
                const SizedBox(height: 16),
                Divider(color: context.borderColor, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onReject();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side: BorderSide(color: colors.error),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text('Tolak'),
                      ),
                    ),
                    if (offer.canCounter) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onCounter();
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: const Text('Tawar Balik'),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onAccept();
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text('Terima'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.captionSemibold(
                    context.appColors.onSurface,
                  ),
                ),
                Text(
                  body,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.entry});

  final OfferHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${entry.actor.label} ',
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
                TextSpan(
                  text: entry.action.label,
                  style: AppTypography.caption(context.mutedForeground),
                ),
                if (entry.price != null)
                  TextSpan(
                    text: ' ${formatRupiah(entry.price!)}',
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                TextSpan(
                  text: ' · ${formatRelativeId(entry.at)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          if (entry.message != null && entry.message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 1),
              child: Text(
                '“${entry.message}”',
                style: AppTypography.caption(
                  context.mutedForeground,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

Color _toneColor(BuildContext context, ListingOffer offer) {
  final colors = context.appColors;
  final state = offer.paymentState;
  if (state != null) {
    return switch (state) {
      OfferPaymentState.awaiting => colors.tertiary,
      OfferPaymentState.paid => context.appColors.primary,
      OfferPaymentState.cancelled => colors.error,
      OfferPaymentState.expired => context.mutedForeground,
    };
  }
  return switch (offer.status) {
    OfferStatus.pending => colors.tertiary,
    OfferStatus.accepted => colors.primary,
    OfferStatus.rejected => colors.error,
    OfferStatus.withdrawn || OfferStatus.expired => context.mutedForeground,
  };
}

/// How long the buyer's offer stays open. Counted in whole units and rounded
/// up, so an offer with 90 minutes left never reads "1 jam" and expires
/// early in the seller's head.
String _countdown(Duration left) {
  if (left == Duration.zero) return 'Penawaran sudah kadaluwarsa';
  if (left.inHours >= 24) {
    return 'Berakhir dalam ${(left.inHours / 24).ceil()} hari';
  }
  if (left.inMinutes >= 60) {
    return 'Berakhir dalam ${(left.inMinutes / 60).ceil()} jam';
  }
  return 'Berakhir dalam ${left.inMinutes} menit';
}
