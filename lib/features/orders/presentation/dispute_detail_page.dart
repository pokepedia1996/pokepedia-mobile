import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/photo_strip.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/dispute_model.dart';
import '../usecase/orders_notifier.dart';
import '../utils/dispute_gating.dart';
import 'widgets/dispute_actions.dart';

/// Ports `features/disputes/ui/components/common/dispute-detail-page.tsx` for
/// both parties: the dispute's state, what the viewer can do about it, the
/// discussion with its evidence, and the event history.
///
/// Reached by dispute slug (`/disputes/:slug`, the seller's way in and every
/// notification's), or by order (`/orders/:slug/dispute`), which resolves to
/// the order's open dispute first.
class DisputeDetailPage extends ConsumerWidget {
  const DisputeDetailPage({super.key, required this.disputeSlug})
    : orderSlug = null;

  const DisputeDetailPage.forOrder({super.key, required String this.orderSlug})
    : disputeSlug = null;

  final String? disputeSlug;
  final String? orderSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget body;
    if (disputeSlug != null) {
      body = _DisputeBody(slug: disputeSlug!);
    } else {
      body = ref
          .watch(orderDisputeProvider(orderSlug!))
          .when(
            data: (slug) => slug == null
                ? const EmptyState(
                    icon: LucideIcons.gavel,
                    title: 'Belum ada komplain untuk pesanan ini',
                  )
                : _DisputeBody(slug: slug),
            loading: () => const PikachuLoader(),
            error: (_, __) => const _LoadError(),
          );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(child: body),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Gagal memuat komplain'));
}

class _DisputeBody extends ConsumerWidget {
  const _DisputeBody({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return ref
        .watch(disputeDetailProvider(slug))
        .when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const PikachuLoader(),
          error: (_, __) => const _LoadError(),
          data: (dispute) {
            if (dispute == null) {
              return const EmptyState(
                icon: LucideIcons.gavel,
                title: 'Komplain tidak ditemukan',
              );
            }
            final siblings =
                ref.watch(siblingDisputesProvider(slug)).valueOrNull ??
                const [];
            return RefreshIndicator(
              onRefresh: () => ref.refresh(disputeDetailProvider(slug).future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                // Web's order on a phone: the header, then the main column
                // (actions, discussion, history), then the sidebar (summary,
                // sibling disputes, return resi) stacked beneath it.
                children: [
                  Text(
                    'Detail komplain',
                    style: AppTypography.h2(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dispute.slug.toUpperCase(),
                    style: AppTypography.bodySmSemibold(
                      context.mutedForeground,
                    ),
                  ),
                  if (showsHeaderEscalate(dispute)) ...[
                    const SizedBox(height: 12),
                    DisputeEscalateButton(dispute: dispute),
                  ],
                  if (dispute.currentStatus.isActive) ...[
                    const SizedBox(height: 16),
                    switch (dispute.role) {
                      DisputeRole.buyer => BuyerDisputeActionsPanel(
                        dispute: dispute,
                      ),
                      DisputeRole.seller => SellerDisputeActionsPanel(
                        dispute: dispute,
                      ),
                    },
                  ],
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Diskusi & bukti',
                    child: _Discussion(dispute: dispute),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Riwayat',
                    child: dispute.events.isEmpty
                        ? Text(
                            'Belum ada aktivitas.',
                            style: AppTypography.bodySm(
                              context.mutedForeground,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < dispute.events.length; i++)
                                _EventTile(
                                  event: dispute.events[i],
                                  isLast: i == dispute.events.length - 1,
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(dispute: dispute),
                  if (siblings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SiblingBanner(siblings: siblings, role: dispute.role),
                  ],
                  if (dispute.returnTracking != null) ...[
                    const SizedBox(height: 16),
                    _ReturnTrackingPanel(dispute: dispute),
                  ],
                ],
              ),
            );
          },
        );
  }
}

/// The card, the reason, the deadline and the money — web's sidebar
/// (`DisputeCardSummary` + `DisputeMetaPanel`), stacked for a phone.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final item = dispute.item;
    final deadline = disputeDeadline(dispute);
    final muted = AppTypography.caption(context.mutedForeground);
    final orderRef = item?.orderNumber ?? item?.packageOrderNumber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: CardArt(imageUrl: item.cardImageUrl),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.cardName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if ((item.expansionCode ?? '').isNotEmpty)
                            item.expansionCode!.toUpperCase(),
                          if ((item.collectorNumber ?? '').isNotEmpty)
                            '#${item.collectorNumber}',
                          if (dispute.condition != null)
                            dispute.condition!.short,
                          if (item.matchedQuantity != null)
                            '${item.matchedQuantity}x',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Stacked, not side by side: "Menunggu Respons Pembeli" alone is
          // most of a phone's width.
          _StatusPill(dispute: dispute),
          const SizedBox(height: 8),
          Text(
            dispute.reasonCategory.label,
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          if (dispute.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              dispute.reason,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
          if (dispute.reasonCategory == DisputeReasonCategory.short_ &&
              dispute.shortQuantity != null) ...[
            const SizedBox(height: 6),
            Text(
              'Barang kurang: ${dispute.shortQuantity}'
              '${item?.matchedQuantity == null ? '' : ' dari ${item!.matchedQuantity}'} unit',
              style: muted,
            ),
          ],
          if (dispute.requestedResolution != null) ...[
            const SizedBox(height: 6),
            Text(
              'Permintaan pembeli: '
              '${dispute.requestedResolution == 'refund_only' ? 'Pengembalian dana' : 'Pengembalian barang'}',
              style: muted,
            ),
          ],
          if (dispute.outcome != null) ...[
            const SizedBox(height: 6),
            Text(
              'Hasil: ${dispute.outcome!.label}',
              style: AppTypography.captionSemibold(colors.onSurface),
            ),
          ],
          if (deadline != null) ...[
            const SizedBox(height: 10),
            _DeadlineRow(deadline: deadline),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 10),
          _MoneyRow(label: 'Barang', amount: dispute.escrowAmount),
          if (dispute.shippingCost > 0)
            _MoneyRow(label: 'Ongkir', amount: dispute.shippingCost),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dibuka ${formatDeadlineId(dispute.openedAt)}',
                  style: muted,
                ),
              ),
              if (orderRef != null && orderRef.isNotEmpty)
                InkWell(
                  onTap: () => context.push(
                    dispute.role == DisputeRole.seller
                        ? Routes.sellerOrderDetail(orderRef.toLowerCase())
                        : Routes.orderDetail(orderRef.toLowerCase()),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lihat detail pesanan',
                        style: AppTypography.captionSemibold(colors.primary),
                      ),
                      Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A titled section in the same card shell as [_SummaryCard], so every
/// block on the page reads as one of a set.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.h3(context.appColors.onSurface)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final status = dispute.currentStatus;
    final color = !status.isActive
        ? context.appSemantic.success
        : status.inAdminReview
        ? const Color(0xFF3B82F6)
        : context.appColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(status.label, style: AppTypography.captionSemibold(color)),
    );
  }
}

/// Web's `SlaCountdown`, inline: the label, how long is left, and what
/// happens once it passes.
class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});

  final DisputeDeadline deadline;

  @override
  Widget build(BuildContext context) {
    final error = context.appColors.error;
    final left = deadline.at.difference(DateTime.now());
    final passed = left.isNegative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 14, color: error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              passed
                  ? deadline.expiredLabel
                  : '${deadline.label}: ${formatCountdownId(left)} lagi '
                        '(${formatDeadlineId(deadline.at)})',
              style: AppTypography.caption(error),
            ),
          ),
        ],
      ),
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
            style: AppTypography.bodySmSemibold(context.appColors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Web's `SiblingDisputeBanner`.
class _SiblingBanner extends StatelessWidget {
  const _SiblingBanner({required this.siblings, required this.role});

  final List<SiblingDispute> siblings;
  final DisputeRole role;

  @override
  Widget build(BuildContext context) {
    final warn = context.appSemantic.condMp;
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: warn.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 16, color: warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pesanan ini punya ${siblings.length} komplain lain yang '
                  'belum selesai',
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Selesaikan semua komplain dalam paket ini bersama agar tidak ada '
            'yang terlewat.',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 6),
          for (final s in siblings)
            InkWell(
              onTap: () => context.push(Routes.dispute(s.slug)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.cardName} · ${s.orderNumber.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm(colors.onSurface),
                      ),
                    ),
                    Icon(
                      LucideIcons.arrowRight,
                      size: 14,
                      color: context.mutedForeground,
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

class _ReturnTrackingPanel extends StatelessWidget {
  const _ReturnTrackingPanel({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.truck, size: 16, color: context.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resi retur',
                  style: AppTypography.caption(context.mutedForeground),
                ),
                SelectableText(
                  '${(dispute.returnCourier ?? '').toUpperCase()} · '
                  '${dispute.returnTracking}',
                  style: AppTypography.bodySmSemibold(
                    context.appColors.onSurface,
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

/// "Diskusi & bukti" — web's `DisputeEvidenceGallery`: each party's
/// statements and photos as chat bubbles, the viewer's own on the right.
class _Discussion extends StatelessWidget {
  const _Discussion({required this.dispute});

  final DisputeModel dispute;

  static const _roleLabels = {
    'buyer': 'Pembeli',
    'seller': 'Penjual',
    'admin': 'Admin Pokepedia',
  };

  @override
  Widget build(BuildContext context) {
    final messages = groupDisputeMessages(dispute.evidence);
    if (messages.isEmpty) {
      return Text(
        'Belum ada pesan.',
        style: AppTypography.bodySm(context.mutedForeground),
      );
    }
    // Stretched, so each message spans the full width and can push its
    // bubble to the edge — a centered column left short own messages
    // floating off the right edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in messages)
          _MessageBubble(
            message: m,
            roleLabel: _roleLabels[m.role] ?? m.role,
            own: m.role == dispute.role.name,
          ),
      ],
    );
  }
}

/// One message in the discussion, styled after web's gallery: an uppercase
/// role and a full timestamp above a bubble whose corner points at the
/// speaker — the viewer's on the right in the brand tint, the other party's
/// on the left in muted, admin's in blue.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.roleLabel,
    required this.own,
  });

  final DisputeMessage message;
  final String roleLabel;
  final bool own;

  static const _adminBlue = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = context.mutedForeground;
    final m = message;
    final admin = m.role == 'admin';

    final Color fill;
    final Color border;
    if (admin) {
      fill = _adminBlue.withValues(alpha: 0.08);
      border = _adminBlue.withValues(alpha: 0.3);
    } else if (own) {
      fill = colors.primary.withValues(alpha: 0.05);
      border = colors.primary.withValues(alpha: 0.3);
    } else {
      fill = colors.secondary.withValues(alpha: 0.4);
      border = context.borderColor;
    }
    // `rounded-2xl` with the corner nearest the speaker squared off.
    const big = Radius.circular(16);
    const small = Radius.circular(4);
    final radius = BorderRadius.only(
      topLeft: own ? big : small,
      topRight: own ? small : big,
      bottomLeft: big,
      bottomRight: big,
    );
    final stamp =
        '${formatSaleDate(m.submittedAt)}, ${formatClockId(m.submittedAt)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roleLabel.toUpperCase(),
                style: AppTypography.overline(muted),
              ),
              Text('  ·  ', style: AppTypography.caption(muted)),
              Icon(LucideIcons.messageSquare, size: 12, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.85,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.photoUrls.isNotEmpty) ...[
                    PhotoStrip(srcs: m.photoUrls),
                    if (m.statement != null || m.videoUrls.isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  for (final url in m.videoUrls)
                    InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.fileVideo,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tonton video bukti',
                              style: AppTypography.captionSemibold(
                                colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (m.statement != null)
                    Text(
                      m.statement!.trim(),
                      style: AppTypography.bodySm(colors.onSurface),
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

/// One line of "Riwayat" — web's `DisputeTimeline` row.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.isLast});

  final DisputeEvent event;
  final bool isLast;

  static const _actorLabels = {
    'buyer': 'Pembeli',
    'seller': 'Penjual',
    'admin': 'Admin',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final detail = event.detail;
    final actor = _actorLabels[event.actorRole] ?? 'Sistem';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: context.borderColor),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.label,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '$actor · ${formatDeadlineId(event.createdAt)}',
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
