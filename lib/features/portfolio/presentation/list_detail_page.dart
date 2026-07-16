import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../usecase/portfolio_notifier.dart';

/// Ports `app/portfolio/list/[id]/page.tsx`.
class ListDetailPage extends ConsumerWidget {
  const ListDetailPage({super.key, required this.listId});

  final int listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listCardsProvider(listId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail List')),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (cards) {
            if (cards.isEmpty) {
              return const EmptyState(
                icon: Icons.checklist,
                title: 'List ini masih kosong',
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (context, i) =>
                  CardGridItem(card: cards[i], onTap: () {}),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat list')),
        ),
      ),
    );
  }
}
