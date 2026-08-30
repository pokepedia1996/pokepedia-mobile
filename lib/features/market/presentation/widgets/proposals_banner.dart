import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../proposals/repository/models/proposals_summary.dart';
import '../../../proposals/usecase/proposals_notifier.dart';

/// Ports `features/market/feed/components/proposals-banner.tsx` — the way
/// into Proposal from the market page.
///
/// Absent rather than empty for anyone with no stake in proposals: no bids,
/// nothing sent or received, and not selling. Web returns null in that case,
/// and an empty inbox card would be pure noise on a browsing buyer's market
/// page.
class ProposalsBanner extends ConsumerWidget {
  const ProposalsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(proposalsSummaryProvider);

    // A failed summary hides the banner exactly like an empty one, which
    // makes "broken" and "nothing to show" indistinguishable in the field.
    // The user still gets nothing — there is no honest banner to draw — but
    // the reason is at least recoverable from the log.
    if (kDebugMode && async.hasError) {
      debugPrint('[proposals-banner] summary failed: ${async.error}');
    }

    final summary = async.valueOrNull;
    // Nothing while it loads, too: a card that appears a beat later is less
    // jarring than one that appears and then vanishes.
    if (summary == null || !summary.isVisible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Land on whatever the subtitle just described, so the page can
        // actually contain it — "35 bid aktif" pointing at an empty offers
        // tab is what made this look broken.
        onTap: () => context.push(switch (summary.destination) {
          ProposalsDestination.received => Routes.proposalsReceived,
          ProposalsDestination.bids => Routes.proposalsBids,
          ProposalsDestination.sent => Routes.proposalsSent,
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        Icons.inbox_outlined,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                    if (summary.hasNew)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).cardColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Proposal',
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        if (summary.hasNew) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: '${summary.receivedPendingUnseen} baru',
                            background: colors.error,
                            foreground: colors.onPrimary,
                          ),
                        ] else if (summary.totalPending > 0) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: '${summary.totalPending} menunggu',
                            background: colors.secondary,
                            foreground: context.mutedForeground,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: AppTypography.badge(foreground)),
    );
  }
}
