import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/wantlist_model.dart';
import '../usecase/portfolio_notifier.dart';

/// Ports `app/portfolio/list/page.tsx`.
class ListsPage extends ConsumerWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listsProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          data: (lists) {
            if (lists.isEmpty) {
              return const EmptyState(
                icon: Icons.checklist,
                title: 'Belum ada list',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ListTile(list: lists[i]),
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat list')),
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({required this.list});

  final WantlistModel list;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push(Routes.listDetail(list.id)),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.checklist, color: colors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    list.name,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${list.cardCount} kartu · ${list.updatedAt}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}
