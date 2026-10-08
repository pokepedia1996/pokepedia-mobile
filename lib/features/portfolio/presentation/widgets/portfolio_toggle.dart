import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../home/usecase/portfolio_value_notifier.dart';
import 'portfolio_picker_sheet.dart';

/// "Portofolio: Utama ⌄" — the same switcher Beranda and Koleksi carry, so
/// every surface agrees on which portfolio is being worked on. Wherever a
/// card grid has counters, this names the shelf they count against.
class PortfolioToggle extends ConsumerWidget {
  const PortfolioToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final selected = ref.watch(selectedPortfolioProvider);

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => showPortfolioPicker(context, ref),
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.layers,
                size: 13,
                color: context.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                'Portofolio: ',
                style: AppTypography.caption(context.mutedForeground),
              ),
              Flexible(
                child: Text(
                  selected.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: context.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
