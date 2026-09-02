import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/dispute_model.dart';
import '../usecase/orders_notifier.dart';

/// Ports `components/dispute/dispute-detail-page.tsx` +
/// `components/dispute/dispute-timeline.tsx` — a read-only buyer view of an
/// in-progress dispute and its event log.
class DisputeDetailPage extends ConsumerWidget {
  const DisputeDetailPage({super.key, required this.orderSlug});

  final String orderSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDisputeProvider(orderSlug));
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          data: (dispute) {
            if (dispute == null) {
              return const EmptyState(
                icon: LucideIcons.gavel,
                title: 'Belum ada sengketa untuk pesanan ini',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dispute.reasonCategory.label,
                              style: AppTypography.bodySemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                            ),
                            child: Text(
                              dispute.currentStatus.label,
                              style: AppTypography.captionSemibold(
                                colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dispute.reason,
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                      if (dispute.responseDeadline != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.timer,
                              size: 14,
                              color: colors.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Batas respons: ${formatRelativeId(dispute.responseDeadline!)}',
                              style: AppTypography.caption(colors.error),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Riwayat', style: AppTypography.h3(colors.onSurface)),
                const SizedBox(height: 12),
                for (var i = 0; i < dispute.events.length; i++)
                  _EventTile(
                    event: dispute.events[i],
                    isLast: i == dispute.events.length - 1,
                  ),
              ],
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat sengketa')),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.isLast});

  final DisputeEvent event;
  final bool isLast;

  String get _actorLabel {
    switch (event.actorRole) {
      case 'buyer':
        return 'Pembeli';
      case 'seller':
        return 'Penjual';
      case 'admin':
        return 'Admin';
      default:
        return 'Sistem';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 44, color: context.borderColor),
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
                  event.description,
                  style: AppTypography.bodySm(colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_actorLabel · ${formatRelativeId(event.createdAt)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
