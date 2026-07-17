import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../../shared/widgets/pack_card.dart';
import '../usecase/expansions_notifier.dart';

/// Ports `app/expansions/page.tsx` — expansions grouped by series.
class ExpansionsPage extends ConsumerWidget {
  const ExpansionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(seriesGroupsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(),
            Expanded(
              child: async.when(
                data: (groups) {
                  final totalPacks = groups.fold<int>(
                    0,
                    (s, g) => s + g.totalPacks,
                  );
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Text(
                        'Ekspansi',
                        style: AppTypography.h2(context.appColors.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalPacks ekspansi',
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                      const SizedBox(height: 12),
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.series,
                                style: AppTypography.h2(
                                  context.appColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${group.totalPacks} ekspansi · ${group.totalCards} kartu',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: group.packs.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78,
                              ),
                          itemBuilder: (context, i) {
                            final pack = group.packs[i];
                            return PackCard(
                              pack: pack,
                              onTap: () =>
                                  context.push(Routes.packDetail(pack.slug)),
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Gagal memuat ekspansi')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
