import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import 'deck_tab.dart';

/// Ports `app/portfolio/deck` as its own route, matching the web where Deck
/// is a sibling page of Koleksi rather than a tab inside it.
class DeckPage extends ConsumerWidget {
  const DeckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: user == null
            ? EmptyState(
                icon: Icons.grid_view_rounded,
                title: 'Masuk untuk melihat deck',
                description: 'Susun dan simpan deck kartu Pokemon-mu.',
                action: ElevatedButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Masuk'),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Deck',
                      style: AppTypography.h2(context.appColors.onSurface),
                    ),
                  ),
                  const Expanded(child: DeckTab()),
                ],
              ),
      ),
    );
  }
}
