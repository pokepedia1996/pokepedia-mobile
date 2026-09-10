import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../../shared/widgets/catalog_language_toggle.dart';
import '../../../shared/widgets/expansion_list_item.dart';
import '../../../shared/widgets/pack_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../usecase/expansions_notifier.dart';
import '../utils/pack_sort.dart';

/// Ports `features/expansions/components/expansions-list-client.tsx` — the
/// Ekspansi tab: a sort + view toolbar over the expansions, grouped by
/// series while sorted by date and flattened when sorted by name.
///
/// The ID/EN/JP switch scopes which language's catalog is shown, like the
/// web's localized `/en/expansions` routes. Its ad slots between series are
/// skipped — the app has no ad placements.
class ExpansionsPage extends ConsumerStatefulWidget {
  const ExpansionsPage({super.key});

  @override
  ConsumerState<ExpansionsPage> createState() => _ExpansionsPageState();
}

/// How many expansions a series shows before asking to be opened.
///
/// A long series runs to twenty-odd packs, and stacking every one of them
/// turns the page into a scroll with no shape — the series after it are
/// effectively unreachable. Four rather than six: two rows of the two-up
/// grid, so a series takes a predictable bite of the screen and the next
/// one is always in reach.
const _packsPerSeries = 4;

class _ExpansionsPageState extends ConsumerState<ExpansionsPage> {
  PackSortOption _sortBy = PackSortOption.newest;
  CardViewMode _viewMode = CardViewMode.grid;

  /// Series the reader has opened up. Held here rather than per-section so
  /// it survives the list rebuilding as sort and view mode change.
  final _expandedSeries = <String>{};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(seriesGroupsProvider);

    return Scaffold(
      // `bottom: false` lets the list run under the floating nav pill —
      // the scroll padding below keeps the last row clear of it.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopBar(),
            Expanded(
              child: async.when(
                data: (groups) => _buildBody(groups),
                loading: () => const PikachuLoader(),
                error: (_, __) =>
                    const Center(child: Text('Gagal memuat ekspansi')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<SeriesGroup> groups) {
    final totalPacks = groups.fold<int>(0, (sum, g) => sum + g.totalPacks);
    final padding = EdgeInsets.fromLTRB(
      16,
      4,
      16,
      AppBottomNav.reservedSpace(context) + 12,
    );

    // Sorting by name drops the series grouping, matching web's `isGrouped`.
    if (!_sortBy.isGrouped) {
      final packs = sortPacks([
        for (final group in groups) ...group.packs,
      ], _sortBy);
      return ListView(
        padding: padding,
        children: [
          _Toolbar(
            totalPacks: totalPacks,
            sortBy: _sortBy,
            viewMode: _viewMode,
            onSortChanged: (value) => setState(() => _sortBy = value),
            onViewModeChanged: (value) => setState(() => _viewMode = value),
          ),
          const SizedBox(height: 12),
          _PackCollection(packs: packs, viewMode: _viewMode),
        ],
      );
    }

    final ordered = _sortBy == PackSortOption.oldest
        ? groups.reversed.toList()
        : groups;

    return ListView(
      padding: padding,
      children: [
        _Toolbar(
          totalPacks: totalPacks,
          sortBy: _sortBy,
          viewMode: _viewMode,
          onSortChanged: (value) => setState(() => _sortBy = value),
          onViewModeChanged: (value) => setState(() => _viewMode = value),
        ),
        for (final group in ordered) ...[
          const SizedBox(height: 20),
          _SeriesHeader(group: group),
          const SizedBox(height: 12),
          ..._seriesSection(group),
        ],
      ],
    );
  }

  /// One series' packs, capped at [_packsPerSeries] until it is opened.
  List<Widget> _seriesSection(SeriesGroup group) {
    final packs = sortPacks(group.packs, _sortBy);
    final expanded = _expandedSeries.contains(group.series);
    final hidden = packs.length - _packsPerSeries;

    return [
      _PackCollection(
        packs: expanded ? packs : packs.take(_packsPerSeries).toList(),
        viewMode: _viewMode,
      ),
      if (hidden > 0) ...[
        const SizedBox(height: 4),
        _SeriesShowAll(
          expanded: expanded,
          hidden: hidden,
          onToggle: () => setState(() {
            if (!_expandedSeries.remove(group.series)) {
              _expandedSeries.add(group.series);
            }
          }),
        ),
      ],
    ];
  }
}

/// The "Lihat semua" control under a truncated series.
class _SeriesShowAll extends StatelessWidget {
  const _SeriesShowAll({
    required this.expanded,
    required this.hidden,
    required this.onToggle,
  });

  final bool expanded;
  final int hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onToggle,
        icon: Icon(
          expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
          size: 16,
        ),
        // The count is the reason to tap: "Lihat semua" alone doesn't say
        // whether it hides two expansions or twenty.
        label: Text(
          expanded ? 'Tampilkan lebih sedikit' : 'Lihat semua ($hidden lagi)',
        ),
        style: TextButton.styleFrom(foregroundColor: colors.primary),
      ),
    );
  }
}

/// The catalog language switch over a row of sort control, pack count and
/// grid/list toggle — the same stack the web puts above its series list.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.totalPacks,
    required this.sortBy,
    required this.viewMode,
    required this.onSortChanged,
    required this.onViewModeChanged,
  });

  final int totalPacks;
  final PackSortOption sortBy;
  final CardViewMode viewMode;
  final ValueChanged<PackSortOption> onSortChanged;
  final ValueChanged<CardViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: CatalogLanguageToggle(),
        ),
        Row(
          children: [
            _SortButton(sortBy: sortBy, onChanged: onSortChanged),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$totalPacks ekspansi',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            ViewModeToggle(value: viewMode, onChanged: onViewModeChanged),
          ],
        ),
      ],
    );
  }
}

/// Ports `SortDropdown` for the four pack sort options.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sortBy, required this.onChanged});

  final PackSortOption sortBy;
  final ValueChanged<PackSortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PackSortOption>(
      initialValue: sortBy,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: context.borderColor),
      ),
      itemBuilder: (context) => [
        for (final option in PackSortOption.values)
          PopupMenuItem(
            value: option,
            height: 42,
            child: Row(
              children: [
                if (option == sortBy)
                  Icon(
                    LucideIcons.check,
                    size: 16,
                    color: context.appColors.primary,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(
                  option.labelId,
                  style: AppTypography.bodySm(context.appColors.onSurface),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sortBy.labelId,
              style: AppTypography.captionSemibold(context.mutedForeground),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// The box every series wordmark is drawn into.
///
/// Wide enough for a long logo to stay legible, narrow enough that it can't
/// crowd out the series name beside it.
const _seriesLogoWidth = 104.0;
const _seriesLogoHeight = 48.0;

/// The series wordmark (when the series has one) beside its name and counts.
class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({required this.group});

  final SeriesGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final image = group.seriesImageUrl;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (image != null) ...[
          // A fixed box, not a fixed height: these wordmarks range from
          // roughly square to very wide, and with only the height pinned a
          // long one (Matahari & Bulan) ran away with the row and squeezed
          // the series name into a couple of characters. `contain` inside a
          // set box means every series header is the same size whatever the
          // logo's proportions.
          SizedBox(
            width: _seriesLogoWidth,
            height: _seriesLogoHeight,
            child: Image.network(
              image,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.series, style: AppTypography.h2(colors.onSurface)),
              const SizedBox(height: 2),
              Text(
                '${group.totalPacks} ekspansi · ${group.totalCards} kartu',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One batch of packs in whichever view mode is active.
class _PackCollection extends StatelessWidget {
  const _PackCollection({required this.packs, required this.viewMode});

  final List<PackModel> packs;
  final CardViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    if (viewMode == CardViewMode.list) {
      return Column(
        children: [
          for (final pack in packs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ExpansionListItem(
                pack: pack,
                onTap: () => context.push(Routes.packDetail(pack.slug)),
              ),
            ),
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: packs.length,
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
    );
  }
}
