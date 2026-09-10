import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../home/repository/models/portfolio_value.dart';
import '../../../home/usecase/portfolio_value_notifier.dart';
import '../../repository/models/wantlist_model.dart';
import '../../usecase/portfolio_notifier.dart';
import 'portfolio_picker_sheet.dart';

/// How a destination reads inside a sentence. The main collection is named
/// "Utama" because on screen it always follows the word "Portfolio"; on its
/// own it needs the noun back.
String portfolioDestinationLabel(PortfolioTarget target) =>
    target.isPrimary ? 'Koleksi Utama' : target.name;

/// Asks which portfolio incoming cards should be stored in.
///
/// Returns the chosen destination, or null when the user backed out — which
/// every caller treats as "add nothing", since the destination question is
/// asked before the write, not after.
///
/// Every portfolio is a shelf of its own: picking a list puts the copies in
/// that list and nowhere else, and the main collection (`user_cards`) is
/// written only when the main collection is what was picked. Nothing lands
/// in Utama by default.
///
/// Skipped when the user has no lists: the main collection is then the only
/// possible answer, and a one-row sheet is just a tap in the way.
Future<PortfolioTarget?> showAddDestinationSheet(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Simpan ke portofolio',
  String? subtitle,
}) async {
  // Awaited rather than read off `.valueOrNull`: a caller like the card
  // detail page may never have watched the lists, and a null there would
  // look exactly like "no lists" and silently skip the choice.
  List<WantlistModel> lists;
  try {
    lists = await ref.read(listsProvider.future);
  } catch (_) {
    // Nothing to choose between if we can't see the lists; the card still
    // has a home in the collection.
    lists = const [];
  }
  if (lists.isEmpty) return PortfolioTarget.primary;
  if (!context.mounted) return null;

  final result = await showModalBottomSheet<_DestinationResult>(
    context: context,
    // The root navigator for the same reason the portfolio picker uses it,
    // and because callers open this from inside their own sheets.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    // A Consumer so a list created from the header row shows up in place.
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final colors = sheetContext.appColors;
        final rows =
            sheetRef.watch(listsProvider).valueOrNull ??
            const <WantlistModel>[];
        // The portfolio currently on screen — the likeliest answer, so it's
        // the one drawn in the accent colour.
        final current = sheetRef.watch(selectedPortfolioProvider);

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.h3(colors.onSurface),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(const _NewListRequest()),
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Buat list'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      subtitle,
                      style: AppTypography.bodySm(sheetContext.mutedForeground),
                    ),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    children: [
                      _DestinationRow(
                        icon: LucideIcons.layers,
                        name: portfolioDestinationLabel(
                          PortfolioTarget.primary,
                        ),
                        caption: 'Koleksi utama kamu',
                        highlighted: current.isPrimary,
                        onTap: () => Navigator.of(sheetContext).pop(
                          const _PickedDestination(PortfolioTarget.primary),
                        ),
                      ),
                      for (final list in rows)
                        _DestinationRow(
                          icon: LucideIcons.bookmark,
                          name: list.name,
                          caption: '${list.cardCount} kartu',
                          highlighted: current.listId == list.id,
                          onTap: () => Navigator.of(sheetContext).pop(
                            _PickedDestination(
                              PortfolioTarget(name: list.name, listId: list.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  switch (result) {
    case _PickedDestination(:final target):
      return target;
    // Making a list here is a way of naming where the cards should go, so
    // the new one becomes the destination rather than dropping the user
    // back into the picker.
    case _NewListRequest():
      if (!context.mounted) return null;
      final list = await createPortfolioList(context, ref);
      if (list == null) return null;
      return PortfolioTarget(name: list.name, listId: list.id);
    case null:
      return null;
  }
}

/// What the destination sheet came back with.
sealed class _DestinationResult {
  const _DestinationResult();
}

class _PickedDestination extends _DestinationResult {
  const _PickedDestination(this.target);
  final PortfolioTarget target;
}

class _NewListRequest extends _DestinationResult {
  const _NewListRequest();
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.icon,
    required this.name,
    required this.caption,
    required this.highlighted,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String caption;

  /// The portfolio the user is already looking at — marked, not preselected:
  /// nothing is chosen until a row is tapped.
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = highlighted ? colors.primary : context.mutedForeground;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: highlighted
                        ? AppTypography.bodySmSemibold(colors.primary)
                        : AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    caption,
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
          ],
        ),
      ),
    );
  }
}
