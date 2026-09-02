import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import 'inventory_tab.dart';

/// Ports `app/portfolio/inventory` as its own route, matching the web where
/// Inventori is a sibling page of Koleksi rather than a tab inside it.
class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: user == null
            ? EmptyState(
                icon: LucideIcons.package,
                title: 'Masuk untuk melihat inventori',
                description:
                    'Catat modal dan stok kartu yang kamu punya untuk dijual.',
                action: ElevatedButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Masuk'),
                ),
              )
            : const InventoryTab(),
      ),
    );
  }
}
