import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/catalog_language_provider.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_model.dart';

/// Ports `components/layout/language-toggle.tsx` — the ID / EN / JP switch
/// that picks which language's catalog to browse.
///
/// The web navigates to a localized URL on select; here it just moves
/// [catalogLanguageProvider], which the expansions and search queries watch.
class CatalogLanguageToggle extends ConsumerWidget {
  const CatalogLanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(catalogLanguageProvider);
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.5),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final language in catalogLanguages)
            _LanguageButton(
              language: language,
              selected: language == current,
              onTap: () =>
                  ref.read(catalogLanguageProvider.notifier).set(language),
            ),
        ],
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final CardLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tampilkan katalog ${language.labelId}',
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).cardColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                language.flag,
                style: const TextStyle(fontSize: 13, height: 1),
              ),
              const SizedBox(width: 5),
              Text(
                language.shortLabel,
                style: AppTypography.captionSemibold(
                  selected ? colors.onSurface : context.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
