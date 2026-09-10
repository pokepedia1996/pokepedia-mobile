import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/pack_model.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../../shared/widgets/pokeball_icon.dart';
import '../../usecase/home_notifier.dart';

/// Ports `components/home/recently-viewed-expansions.tsx`.
class RecentlyViewedSection extends ConsumerWidget {
  const RecentlyViewedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentlyViewedPacksProvider);
    return async.when(
      data: (packs) {
        if (packs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Terakhir dilihat',
                  style: AppTypography.h3(context.appColors.onSurface),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: packs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _RecentPackChip(pack: packs[i]),
                ),
              ),
            ],
          ),
        );
      },
      loading: () =>
          // 120, not 108: the caption adds a second line under Pikachu and
          // the old box clipped it by 11.
          const SizedBox(height: 120, child: PikachuLoader(size: 96)),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RecentPackChip extends StatelessWidget {
  const _RecentPackChip({required this.pack});

  final PackModel pack;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push(Routes.packDetail(pack.slug)),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 88,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: PokeballIcon(size: 22, color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pack.mark,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionSemibold(colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
