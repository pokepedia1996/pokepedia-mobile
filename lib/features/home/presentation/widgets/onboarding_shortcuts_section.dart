import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../market/usecase/market_notifier.dart';
import '../../../onboarding/usecase/onboarding_intents.dart';

/// "Lanjutkan": what a new user picked on onboarding's "Mau ngapain?" step
/// beyond the first, which is where they already landed. A card each,
/// until it is used to go there or closed.
///
/// Absent when there is nothing left: after "Lewati dulu", after one pick,
/// or once every card is closed.
class OnboardingShortcutsSection extends ConsumerWidget {
  const OnboardingShortcutsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(onboardingIntentsProvider).shortcuts;
    if (shortcuts.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lanjutkan', style: AppTypography.h3(colors.onSurface)),
          const SizedBox(height: 10),
          for (final intent in shortcuts) ...[
            _ShortcutCard(
              intent: intent,
              onOpen: () {
                if (intent == OnboardingIntent.bid) {
                  ref.read(marketWtbTipProvider.notifier).state = true;
                }
                context.go(intent.route);
              },
              onDismiss: () =>
                  ref.read(onboardingIntentsProvider.notifier).dismiss(intent),
            ),
            if (intent != shortcuts.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.intent,
    required this.onOpen,
    required this.onDismiss,
  });

  final OnboardingIntent intent;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(intent.icon, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intent.title,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      intent.description,
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
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(LucideIcons.x, size: 16),
                tooltip: 'Sembunyikan',
                color: context.mutedForeground,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
