import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../orders/repository/models/seller_order.dart';
import '../../../proposals/usecase/proposals_notifier.dart';
import '../../../seller/usecase/seller_notifier.dart';

/// What needs answering, at the top of Beranda — eBay's "Paid · Ship Now"
/// strip, with the count in a circle and the job beside it.
///
/// Only ever what is actually outstanding: a row appears when its count is
/// above zero and the section disappears entirely when none of them are. A
/// standing list of zeroes is the thing that teaches people to scroll past
/// this part of a home screen.
class HomeTasksSection extends ConsumerWidget {
  const HomeTasksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).valueOrNull == null) {
      return const SizedBox.shrink();
    }

    // The seller half is only asked for when there is a shop — the dashboard
    // payload is a real query, and a buyer has no answer in it.
    final hasStore = ref.watch(hasStoreProvider).valueOrNull ?? false;
    final kpi = hasStore
        ? ref.watch(sellerDashboardProvider).valueOrNull?.kpi
        : null;
    final proposals = ref.watch(proposalsSummaryProvider).valueOrNull;

    final tasks = <_Task>[
      if ((kpi?.toShip ?? 0) > 0)
        _Task(
          count: kpi!.toShip,
          title: 'Perlu dikirim',
          subtitle: 'Pesanan menunggu dikirim',
          icon: LucideIcons.package,
          tone: _Tone.warning,
          route: Routes.sellerOrdersFiltered(SellerOrderTab.urgent.filterKey),
        ),
      if ((kpi?.disputesOpen ?? 0) > 0)
        _Task(
          count: kpi!.disputesOpen,
          title: 'Komplain terbuka',
          subtitle: 'Pembeli menunggu jawabanmu',
          icon: LucideIcons.shieldAlert,
          tone: _Tone.danger,
          route: Routes.sellerOrdersFiltered(SellerOrderTab.disputed.filterKey),
        ),
      if ((proposals?.receivedPending ?? 0) > 0)
        _Task(
          count: proposals!.receivedPending,
          title: 'Proposal masuk',
          subtitle: 'Penjual menawarkan kartu untuk bid kamu',
          icon: LucideIcons.handCoins,
          tone: _Tone.warning,
          route: Routes.proposalsReceived,
        ),
    ];

    if (tasks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            for (var i = 0; i < tasks.length; i++) ...[
              if (i > 0) Divider(height: 1, color: context.borderColor),
              _TaskRow(task: tasks[i]),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Tone { warning, danger }

class _Task {
  const _Task({
    required this.count,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.route,
  });

  final int count;
  final String title;
  final String subtitle;
  final IconData icon;
  final _Tone tone;
  final String route;
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final _Task task;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = task.tone == _Tone.danger
        ? colors.error
        : context.appSemantic.condMp;

    return InkWell(
      onTap: () => context.push(task.route),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            // The count first and in a circle, the way eBay leads with it:
            // the number is the reason to look.
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Text(
                task.count > 99 ? '99+' : '${task.count}',
                style: AppTypography.bodySmSemibold(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(tint),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    task.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
