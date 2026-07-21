import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../shared/widgets/pack_card.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../usecase/home_notifier.dart';

/// Ports `components/home/explore-expansions.tsx`.
class ExploreExpansionsSection extends ConsumerWidget {
  const ExploreExpansionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(explorePacksProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SectionHeader(
            title: 'Jelajahi Ekspansi',
            subtitle: 'Koleksi lengkap set kartu Pokémon TCG',
            trailing: TextButton(
              onPressed: () => context.go(Routes.expansions),
              child: const Text('Lihat semua'),
            ),
          ),
          const SizedBox(height: 12),
          async.when(
            data: (packs) => GridView.builder(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: packs.take(4).length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.84,
              ),
              itemBuilder: (context, i) {
                final pack = packs[i];
                return PackCard(
                  pack: pack,
                  onTap: () => context.push(Routes.packDetail(pack.slug)),
                );
              },
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
