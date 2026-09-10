import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'widgets/courier_tracking_link.dart';
import '../../../shared/utils/courier.dart';
import 'widgets/cancel_order_sheet.dart';
import '../../../app/router/routes.dart';
import '../../cart/presentation/payment_webview_page.dart';
import '../../chat/repository/models/chat_models.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/order_model.dart';
import '../repository/models/shipment_destination.dart';
import '../usecase/orders_notifier.dart';
import '../utils/order_status_display.dart';
import 'widgets/order_rating_section.dart';
import 'widgets/tracking_timeline.dart';
import 'widgets/order_thumbnail.dart';

/// Ports `features/orders/components/detail/order-detail.tsx`.
///
/// Web lays this out as a main column plus a right rail; a phone has one
/// column, so the rail's cards (Pembayaran, Riwayat) fall to the bottom in
/// the order a buyer would reach for them.
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _confirmReceipt(OrderModel order) {
    final itemId = order.firstItemId;
    if (itemId == null) return Future.value();

    return showConfirmDialog(
      context,
      title: 'Konfirmasi Penerimaan?',
      description:
          'Dana akan diteruskan ke penjual. Lakukan hanya setelah kartu '
          'kamu terima dan sesuai.',
      confirmLabel: 'Konfirmasi',
      loadingLabel: 'Mengonfirmasi...',
      onConfirm: () async {
        setState(() => _busy = true);
        final error = await ref
            .read(ordersRepositoryProvider)
            .confirmReceipt(itemId);
        if (!mounted) return;
        setState(() => _busy = false);
        _toast(error ?? 'Penerimaan dikonfirmasi');
        if (error == null) ref.invalidate(orderDetailProvider(widget.slug));
      },
    );
  }

  /// Opens the room with this order's seller, creating nothing until
  /// something is said — the same lazy path "Hubungi penjual" takes from a
  /// storefront.
  /// Opens the cancellation sheet and reports what came of it.
  ///
  /// The route takes the `order_items` slug rather than the order's, and a
  /// cancellation either lands immediately or goes to the seller to approve
  /// — web branches its confirmation on the same flag.
  Future<void> _cancelOrder(OrderModel order) async {
    final itemSlug = order.items.firstOrNull?.slug;
    if (itemSlug == null) return;

    final instant = await showCancelOrderSheet(context, itemSlug: itemSlug);
    if (instant == null || !mounted) return;

    ref.invalidate(orderDetailProvider(widget.slug));
    ref.invalidate(ordersProvider);

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          instant
              ? 'Pesanan dibatalkan. Dana dikembalikan penuh.'
              : 'Permintaan pembatalan dikirim ke penjual.',
        ),
      ),
    );
  }

  Future<void> _contactSeller(OrderModel order) async {
    final sellerId = order.sellerId;
    if (sellerId == null) return;

    final arg = await ref
        .read(chatOpenerProvider)
        .withUser(otherUserId: sellerId, title: order.storeName);
    if (!mounted) return;

    final slug = arg.slug;
    if (slug != null) {
      context.push(Routes.chatThread(slug), extra: order.storeName);
    } else {
      context.push(
        Routes.chatNew,
        extra: ChatTarget(otherUserId: sellerId, title: order.storeName),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(orderDetailProvider(widget.slug));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat pesanan')),
          data: (order) {
            if (order == null) {
              return const EmptyState(
                icon: LucideIcons.receipt,
                title: 'Pesanan tidak ditemukan',
              );
            }

            // Resolved once. The page used to re-derive "is it shipped",
            // "is it disputed" and "can it be confirmed" at each call site,
            // which is how the sections drifted out of step with each other.
            final s = BuyerOrderStates(order);

            // The action bar is a sibling of the list rather than its last
            // row: web pins it to the bottom of the viewport
            // (`fixed inset-x-0 bottom-0`), and the buyer should not have to
            // scroll to the end of a long order to reach "Batalkan Pesanan".
            return Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(orderDetailProvider(widget.slug));
                      await ref.read(orderDetailProvider(widget.slug).future);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        // Web's header: the title, then the package number under
                        // it. The status belongs to the Pesanan card below, not
                        // beside the number.
                        Text(
                          'Detail pesanan',
                          style: AppTypography.h1(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.orderNumber.toUpperCase(),
                          style: AppTypography.bodySmSemibold(
                            context.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Web puts the destination first at mobile width — it's
                        // the fact a buyer opens this page to check.
                        if (order.destination case final address?
                            when !address.isEmpty) ...[
                          _AddressCard(address: address),
                          const SizedBox(height: 12),
                        ],

                        // Web shows this while the seller is preparing, in place
                        // of tracking that doesn't exist yet.
                        if (s.preparing) ...[
                          _Section(
                            icon: LucideIcons.package,
                            title: 'Penjual sedang menyiapkan pesanan',
                            children: [
                              Text(
                                order.shipmentDeadline == null
                                    ? 'Status pelacakan muncul di sini setelah '
                                          'paket dikirim.'
                                    : 'Pesanan akan dikirim sebelum '
                                          '${formatShortDateId(order.shipmentDeadline!)}. '
                                          'Status pelacakan muncul di sini setelah '
                                          'paket dikirim.',
                                style: AppTypography.bodySm(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // A cancellation the seller hasn't answered outranks
                        // everything below: it's the thing the buyer is waiting on.
                        if (s.cancelPending) ...[
                          _CancelPendingCard(order: order),
                          const SizedBox(height: 12),
                        ],

                        // Web's order below the header is items, then the order's
                        // standing and who it's from, then tracking. Mobile led
                        // with the seller and put tracking above the items, which
                        // is the reordering that made the two screens read
                        // differently.
                        _ItemsSection(order: order),
                        const SizedBox(height: 12),

                        _OrderStatusCard(order: order),
                        const SizedBox(height: 12),

                        // `showLacakPaket`: a dispatched parcel gets this section
                        // even before a resi exists. Gating on the tracking number
                        // hid it exactly when the buyer wanted it most.
                        if (s.showTracking) ...[
                          _TrackingCard(
                            order: order,
                            states: s,
                            busy: _busy,
                            onConfirmReceipt: () => _confirmReceipt(order),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (OrderRatingSection.isReviewable(order)) ...[
                          const SizedBox(height: 12),
                          OrderRatingSection(
                            order: order,
                            child: (title, children) =>
                                _Section(title: title, children: children),
                          ),
                        ],

                        // The unpaid stage. Web leads with what's owed and the
                        // deadline; the app showed nothing at all, so an unpaid
                        // order had no way to be paid from here.
                        if (s.isUnpaid) ...[
                          _UnpaidCard(
                            order: order,
                            onPay: order.invoiceUrl == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PaymentWebViewPage(
                                        invoiceUrl: order.invoiceUrl!,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        _PaymentCard(order: order),
                      ],
                    ),
                  ),
                ),
                _BuyerActions(
                  order: order,
                  states: s,
                  onOpenDispute: () =>
                      context.push(Routes.orderOpenDispute(widget.slug)),
                  onViewDispute: () =>
                      context.push(Routes.orderDispute(widget.slug)),
                  onContactSeller: order.sellerId == null
                      ? null
                      : () => _contactSeller(order),
                  onCancel: () => _cancelOrder(order),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Web's card shell: a bordered box with an optional titled header.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
    this.padded = true,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;

  /// The right-hand side of the header — web puts an item count there.
  final Widget? trailing;

  /// False lets the body run to the card's edges, so a list can carry
  /// full-bleed dividers between its rows the way web's `divide-y` does and
  /// pad each row itself.
  final bool padded;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Web's section card is a bordered header strip over a padded
          // body (`header.border-b` + `div.p-5`), not one flat box with a
          // title floating at the top — which is most of why the two
          // screens read differently at a glance.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: context.mutedForeground),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: padded ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ports `order-status-card.tsx` — "Pesanan" with the order's standing on
/// the right, and the seller as a bordered chip underneath.
///
/// Web carries the status here rather than beside the page title, so the
/// word sits with the party it concerns.
class _OrderStatusCard extends StatelessWidget {
  const _OrderStatusCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final display = describeOrderForBuyer(order);
    final slug = order.sellerHandle;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SellerAvatar(
            name: order.storeName,
            imageUrl: order.sellerImageUrl,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                if (order.sellerSecondaryName != null)
                  Text(
                    order.sellerSecondaryName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
              ],
            ),
          ),
          if (slug != null)
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: context.mutedForeground,
            ),
        ],
      ),
    );

    return _Section(
      title: 'Pesanan',
      trailing: StatusPill.tone(label: display.label, tone: display.tone),
      children: [
        Text('PENJUAL', style: AppTypography.overline(context.mutedForeground)),
        const SizedBox(height: 8),
        if (slug == null)
          chip
        else
          InkWell(
            onTap: () => context.push(Routes.storeDetail(slug)),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: chip,
          ),
      ],
    );
  }
}

/// Ports web's `BuyerActionButtons` plus the confirm-receipt block above it.
///
/// One place decides what a buyer may do, in web's order: see the complaint,
/// confirm receipt, or raise a complaint. Previously these were three
/// unrelated `if`s at the bottom of the page, which is why a disputed order
/// still offered "Ajukan Sengketa" and a not-yet-delivered one offered
/// nothing at all with no explanation.
class _BuyerActions extends StatelessWidget {
  const _BuyerActions({
    required this.order,
    required this.states,
    required this.onOpenDispute,
    required this.onViewDispute,
    required this.onContactSeller,
    required this.onCancel,
  });

  final OrderModel order;
  final BuyerOrderStates states;
  final VoidCallback onOpenDispute;
  final VoidCallback onViewDispute;

  /// Opens the cancellation sheet. Only called while
  /// [BuyerOrderStates.canRequestCancel].
  final VoidCallback onCancel;

  /// Null when the order carries no seller id to open a room with.
  final VoidCallback? onContactSeller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final buttons = <Widget>[];
    final notes = <String>[];

    if (states.disputeOpen) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onViewDispute,
          icon: const Icon(LucideIcons.triangleAlert, size: 16),
          label: const Text(
            'Lihat Komplain',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
          ),
        ),
      );
    }

    // Web renders this greyed out rather than removing it once a resi
    // exists, so the option reads as spent rather than as never offered.
    if (states.canRequestCancel || states.showDisabledCancel) {
      buttons.add(
        // Web's `destructive` variant is a tint, not a fill:
        // `border border-destructive/20 bg-destructive/10 text-destructive`.
        // A solid red block reads as the *result* of a destructive action
        // rather than an offer to take one.
        OutlinedButton.icon(
          onPressed: states.canRequestCancel ? onCancel : null,
          label: const Text(
            'Batalkan Pesanan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: colors.error,
            backgroundColor: colors.error.withValues(alpha: 0.10),
            side: BorderSide(color: colors.error.withValues(alpha: 0.20)),
          ),
        ),
      );
      if (states.showDisabledCancel) {
        notes.add(
          'Resi sudah dibuat, tidak bisa dibatalkan. Hubungi penjual '
          'atau laporkan masalah.',
        );
      }
    }

    if (states.showReport) {
      // Shown even when it can't be used yet, with web's explanation —
      // hiding it makes the option look absent rather than not-yet.
      buttons.add(
        OutlinedButton.icon(
          onPressed: states.reportActive ? onOpenDispute : null,
          icon: const Icon(LucideIcons.triangleAlert, size: 16),
          label: const Text(
            'Ajukan Komplain',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: context.appSemantic.condMp,
            side: BorderSide(
              color: context.appSemantic.condMp.withValues(alpha: 0.4),
            ),
          ),
        ),
      );
      if (!states.reportActive) {
        notes.add('Tombol aktif setelah estimasi waktu tiba.');
      }
    }

    // Web keeps this at the end of the bar in every state — reaching the
    // seller shouldn't depend on which stage the order is at.
    if (onContactSeller != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onContactSeller,
          icon: const Icon(LucideIcons.messageCircle, size: 16),
          label: const Text(
            'Hubungi Penjual',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Container(
      // Web's bar: `border-t border-border bg-background/95 px-4 py-3`.
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The notes sit above the row rather than between the buttons:
            // in a single row a stray line of prose would push the controls
            // off the bottom of the bar.
            for (final note in notes) ...[
              Text(note, style: AppTypography.caption(context.mutedForeground)),
              const SizedBox(height: 8),
            ],
            // One row, each button an equal share — web's `flex gap-3` with
            // `flex-1` on every child.
            Row(
              spacing: 12,
              children: [for (final button in buttons) Expanded(child: button)],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnpaidCard extends StatelessWidget {
  const _UnpaidCard({required this.order, required this.onPay});

  final OrderModel order;

  /// Null when the checkout no longer carries an invoice to open.
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final deadline = order.paymentDeadline;

    return _Section(
      icon: LucideIcons.banknote,
      title: 'Menunggu pembayaran',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Total tagihan',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            Text(
              formatRupiah(order.total),
              style: AppTypography.bodySemibold(context.appColors.onSurface),
            ),
          ],
        ),
        if (deadline != null) ...[
          const SizedBox(height: 6),
          Text(
            'Bayar sebelum ${formatDeadlineId(deadline)} atau pesanan '
            'dibatalkan otomatis.',
            style: AppTypography.caption(context.appSemantic.condMp),
          ),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onPay,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
          child: const Text('Bayar Sekarang'),
        ),
        if (onPay == null) ...[
          const SizedBox(height: 6),
          Text(
            'Tagihan untuk pesanan ini sudah tidak tersedia. Hubungi '
            'dukungan jika kamu merasa ini keliru.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ],
    );
  }
}

/// Ports `cancel-pending-card.tsx` — a cancellation waiting on the seller.
class _CancelPendingCard extends StatelessWidget {
  const _CancelPendingCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final reason = order.items
        .map((item) => item.cancelReason)
        .whereType<String>()
        .where((r) => r.trim().isNotEmpty)
        .firstOrNull;

    return _Section(
      icon: LucideIcons.clock,
      title: 'Menunggu konfirmasi penjual',
      children: [
        Text(
          'Permintaan pembatalanmu sudah dikirim. Penjual punya waktu untuk '
          'menyetujui atau menolaknya.',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text(
            'Alasan: $reason',
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
        ],
      ],
    );
  }
}

/// Ports `address-card.tsx` — who the parcel is going to and where.
class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final ShipmentDestination address;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final area = address.areaLine;

    return _Section(
      icon: LucideIcons.mapPin,
      title: 'Alamat pengiriman',
      children: [
        if (address.contactName?.isNotEmpty ?? false)
          Text(
            address.contactName!,
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
        if (address.contactPhone?.isNotEmpty ?? false)
          Text(
            address.contactPhone!,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        if (address.fullAddress?.isNotEmpty ?? false) ...[
          const SizedBox(height: 6),
          Text(
            address.fullAddress!,
            style: AppTypography.bodySm(colors.onSurface),
          ),
        ],
        if (area.isNotEmpty)
          Text(area, style: AppTypography.bodySm(context.mutedForeground)),
      ],
    );
  }
}

/// Ports the tracking block — "Resi" with a copy action, which is the one
/// thing on this page a buyer needs to paste elsewhere.
class _TrackingCard extends StatelessWidget {
  const _TrackingCard({
    required this.order,
    required this.states,
    required this.busy,
    required this.onConfirmReceipt,
  });

  final OrderModel order;
  final BuyerOrderStates states;
  final bool busy;
  final VoidCallback onConfirmReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Nullable now. The section appears as soon as the parcel is dispatched,
    // which can be before a resi exists — the old `trackingNumber!` would
    // have thrown there.
    final tracking = order.trackingNumber;

    return _Section(
      icon: LucideIcons.truck,
      title: 'Lacak paket',
      children: [
        if (tracking != null) ...[
          Row(
            children: [
              Text(
                'Resi',
                style: AppTypography.caption(context.mutedForeground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tracking,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              // `courierDisplayName(shipment.courier)` on web — "J&T Express",
              // not the bare code shouted back as "JNT".
              if (courierDisplayName(order.courier) case final name?)
                Text(
                  '· $name',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Salin nomor resi',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: tracking));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Nomor resi disalin'),
                        persist: false,
                      ),
                    );
                },
                icon: Icon(
                  LucideIcons.copy,
                  size: 16,
                  color: context.mutedForeground,
                ),
              ),
            ],
          ),
          Divider(height: 20, color: context.borderColor),
        ],
        if (order.isUntrackableManual)
          Text(
            'Status pengiriman untuk kurir ini tidak tersedia di aplikasi. '
            'Lacak paket lewat halaman kurir.',
            style: AppTypography.caption(context.mutedForeground),
          )
        else
          TrackingTimeline(order: order),
        // Web's `CourierTrackingLink`, in its slot under the timeline: the
        // way out to the courier's own page, which is the only place an
        // untrackable resi can be looked up at all.
        if (tracking != null) ...[
          const SizedBox(height: 10),
          CourierTrackingLink(courier: order.courier, trackingNumber: tracking),
        ],
        // Web nests `BuyerReceiveAction` here behind `{isShipped && …}`, so
        // the whole block — hint, dispute notice and button — disappears the
        // moment `confirm_receipt` moves the settlement off `shipped`. It
        // used to live at the page bottom gated only on `canConfirm`, which
        // stays true once a delivery timestamp exists, so the button
        // survived its own tap.
        if (states.isShipped) ...[
          Divider(height: 24, color: context.borderColor),
          _ReceiveAction(
            order: order,
            states: states,
            busy: busy,
            onConfirm: onConfirmReceipt,
          ),
        ],
      ],
    );
  }
}

/// Ports `BuyerReceiveAction`: why the button is or isn't available, and the
/// button itself.
class _ReceiveAction extends StatelessWidget {
  const _ReceiveAction({
    required this.order,
    required this.states,
    required this.busy,
    required this.onConfirm,
  });

  final OrderModel order;
  final BuyerOrderStates states;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canConfirm = states.canConfirm;
    final disputeOpen = states.disputeOpen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canConfirm)
          Text(
            'Tombol konfirmasi akan aktif setelah paket sampai di alamat '
            'kamu.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        if (canConfirm && disputeOpen)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appSemantic.condMp.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: context.appSemantic.condMp.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: 16,
                  color: context.appSemantic.condMp,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Komplain kamu sedang ditinjau tim kami. Pelepasan dana '
                    'ke penjual ditahan sementara.',
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
              ],
            ),
          ),
        if (canConfirm && !disputeOpen) ...[
          const SizedBox(height: 4),
          ElevatedButton(
            onPressed: busy ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.appSemantic.success,
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('Konfirmasi Diterima'),
          ),
        ],
      ],
    );
  }
}

class _ItemsSection extends StatefulWidget {
  const _ItemsSection({required this.order});

  final OrderModel order;

  @override
  State<_ItemsSection> createState() => _ItemsSectionState();
}

class _ItemsSectionState extends State<_ItemsSection> {
  bool _showBreakdown = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final order = widget.order;
    final count = order.items.length;

    return _Section(
      title: 'Item dipesan',
      padded: false,
      trailing: Text(
        '$count item${count > 1 ? 's' : ''}',
        style: AppTypography.caption(context.mutedForeground),
      ),
      children: [
        for (var i = 0; i < order.items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: context.borderColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _OrderItemRow(item: order.items[i]),
          ),
        ],
        Divider(height: 1, color: context.borderColor),
        InkWell(
          onTap: () => setState(() => _showBreakdown = !_showBreakdown),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total dibayar',
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ),
                Text(
                  formatRupiah(order.total),
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showBreakdown
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 14,
                  color: context.mutedForeground,
                ),
              ],
            ),
          ),
        ),
        if (_showBreakdown) ...[
          Divider(height: 1, color: context.borderColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoneyRow(
                  label: 'Subtotal ($count item)',
                  amount: order.itemsSubtotal,
                ),
                _MoneyRow(label: 'Ongkir', amount: order.shippingTotal),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          Text(
            formatRupiah(amount),
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Ports `order-item-row.tsx` — a `[64px | 1fr | auto]` row: the square
/// thumbnail, what the card is and which order line it belongs to, then the
/// quantity, unit price and line total stacked on the right.
class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final OrderItemModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderThumbnail(imageUrl: item.card.imageUrl, radius: AppRadius.sm),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.card.expansionCode.isNotEmpty)
                      ExpansionChip(code: item.card.expansionCode),
                    Text(
                      '#${item.card.collectorNumber}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    ConditionBadge(condition: item.condition, dense: true),
                  ],
                ),
                const SizedBox(height: 4),
                // Each line carries its own order number on the web: a
                // package can hold several, and this is the one you quote
                // when only one item is in question.
                Text(
                  item.orderNumber.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '×${item.matchedQuantity}',
                style: AppTypography.caption(context.mutedForeground),
              ),
              Text(
                formatRupiah(item.matchPrice),
                style: AppTypography.caption(context.mutedForeground),
              ),
              const SizedBox(height: 2),
              Text(
                formatRupiah(item.subtotal),
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ports the rail's "Pembayaran" card, which is visible at mobile width —
/// only two of the rail's children are `hidden lg:block`, not the rail.
///
/// Riwayat is a collapsed section *inside* this card on web, not a card of
/// its own, and it lists only the steps that actually happened.
class _PaymentCard extends StatefulWidget {
  const _PaymentCard({required this.order});

  final OrderModel order;

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final order = widget.order;
    final number = order.orderNumber.toUpperCase();

    // `steps.filter((s) => s.at)` — web lists what has happened, not a
    // greyed-out plan of what might. The app used to render all four with
    // an invented "selesai" date.
    final steps = <({String label, DateTime at})>[
      (label: 'Pesanan dibuat', at: order.createdAt),
      if (order.paidAt case final at?) (label: 'Pembayaran diterima', at: at),
      if (order.shippedAt case final at?) (label: 'Pesanan dikirim', at: at),
      if (order.releasedAt case final at?) (label: 'Pesanan selesai', at: at),
    ];

    return _Section(
      icon: LucideIcons.banknote,
      title: 'Pembayaran',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'No. Pesanan',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            Text(number, style: AppTypography.bodySmSemibold(colors.onSurface)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Salin nomor pesanan',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: number));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Nomor pesanan disalin'),
                      persist: false,
                    ),
                  );
              },
              icon: Icon(
                LucideIcons.copy,
                size: 16,
                color: context.mutedForeground,
              ),
            ),
          ],
        ),
        // Web only prints a method when it knows one. The app used to state
        // "Xendit" for any paid order, which was a guess.
        Divider(height: 20, color: context.borderColor),
        InkWell(
          onTap: () => setState(() => _showHistory = !_showHistory),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Riwayat',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ),
              Icon(
                _showHistory ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: context.mutedForeground,
              ),
            ],
          ),
        ),
        if (_showHistory) ...[
          const SizedBox(height: 8),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      step.label,
                      style: AppTypography.bodySm(colors.onSurface),
                    ),
                  ),
                  Text(
                    '${formatShortDateId(step.at)} · '
                    '${formatClockId(step.at)}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
