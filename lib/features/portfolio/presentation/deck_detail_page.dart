import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/deck_card_entry.dart';
import '../usecase/portfolio_notifier.dart';
import '../utils/deck_validation.dart';
import 'deck_form_sheet.dart';

/// Ports `app/portfolio/deck/[id]/page.tsx` + `components/deck/*` — the
/// deck builder. Uses the same "Cari Kartu" / "Deck" two-pane split the web
/// itself falls back to on mobile, but keeps the validity bar visible on
/// both panes (the web buries it inside the Deck pane only) so progress is
/// never hidden while searching.
class DeckDetailPage extends ConsumerStatefulWidget {
  const DeckDetailPage({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends ConsumerState<DeckDetailPage> {
  int _tab = 0;
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _debouncedQuery = '';
  bool _duplicating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _debouncedQuery = v);
    });
  }

  Future<void> _addCard(CardModel card) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .upsertDeckCard(deckId: widget.deckId, cardId: card.id, delta: 1);
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(translateDeckCardError(error))));
    }
  }

  Future<void> _changeQuantity(DeckCardEntry entry, int delta) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .upsertDeckCard(
          deckId: widget.deckId,
          cardId: entry.card.id,
          delta: delta,
        );
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(translateDeckCardError(error))));
    }
  }

  Future<void> _editHeader(String name, String description) async {
    final result =
        await showModalBottomSheet<({String name, String description})>(
          context: context,
          isScrollControlled: true,
          builder: (context) => DeckFormSheet(
            title: 'Edit Deck',
            submitLabel: 'Simpan',
            initialName: name,
            initialDescription: description,
          ),
        );
    if (result == null || !mounted) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .updateDeck(
          deckId: widget.deckId,
          userId: user.id,
          name: result.name,
          description: result.description,
        );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck diperbarui')));
  }

  Future<void> _copyShareLink(String shareCode) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://pokepedia.id/deck/$shareCode'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link disalin ke clipboard')));
  }

  Future<void> _duplicate() async {
    setState(() => _duplicating = true);
    final res = await ref
        .read(cardOwnershipControllerProvider)
        .duplicateDeck(widget.deckId);
    if (!mounted) return;
    setState(() => _duplicating = false);
    if (res.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck berhasil diduplikasi')));
    context.push(Routes.deckDetail(res.deck!.id));
  }

  Future<void> _copyDeckList(
    List<DeckCardEntry> entries,
    DeckValidationResult validation,
  ) async {
    if (entries.isEmpty) return;
    final pokemon = entries
        .where((e) => e.category == DeckCategory.pokemon)
        .toList();
    final trainer = entries
        .where((e) => e.category == DeckCategory.trainer)
        .toList();
    final energy = entries
        .where((e) => e.category == DeckCategory.energy)
        .toList();

    String section(String label, int count, List<DeckCardEntry> group) {
      final lines = group.map(
        (e) =>
            '${e.quantity} ${e.card.name} ${e.card.expansionCode} ${e.card.collectorNumber}',
      );
      return '$label: $count\n${lines.join('\n')}';
    }

    final sections = <String>[
      if (pokemon.isNotEmpty)
        section('Pokemon', validation.pokemonCount, pokemon),
      if (trainer.isNotEmpty)
        section('Trainer', validation.trainerCount, trainer),
      if (energy.isNotEmpty) section('Energy', validation.energyCount, energy),
    ];
    final text = '${sections.join('\n\n')}\n\nTotal: ${validation.totalCards}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daftar deck disalin ke clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decksAsync = ref.watch(decksProvider);
    final deck = decksAsync.valueOrNull
        ?.where((d) => d.id == widget.deckId)
        .firstOrNull;
    final entriesAsync = ref.watch(deckCardsProvider(widget.deckId));

    return Scaffold(
      appBar: TransparentAppBar(
        actions: [
          if (deck != null)
            IconButton(
              icon: const Icon(LucideIcons.pencil, size: 20),
              onPressed: () => _editHeader(deck.name, deck.description),
            ),
        ],
      ),
      body: decksAsync.isLoading && deck == null
          ? const PikachuLoader()
          : deck == null
          ? const EmptyState(
              icon: LucideIcons.searchX,
              title: 'Deck tidak ditemukan',
            )
          : entriesAsync.when(
              data: (entries) {
                final validation = validateDeck(entries);
                return Column(
                  children: [
                    if (deck.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            deck.description,
                            style: AppTypography.bodySm(
                              context.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _copyShareLink(deck.shareCode),
                              icon: const Icon(LucideIcons.link, size: 16),
                              label: const Text('Salin Link'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _duplicating ? null : _duplicate,
                              icon: _duplicating
                                  ? const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(LucideIcons.copy, size: 16),
                              label: const Text('Duplikat'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _DeckValidityBar(validation: validation),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TabChip(
                              label: 'Cari Kartu',
                              selected: _tab == 0,
                              onTap: () => setState(() => _tab = 0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TabChip(
                              label:
                                  'Deck (${validation.totalCards}/$deckMaxCards)',
                              selected: _tab == 1,
                              onTap: () => setState(() => _tab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _tab == 0
                          ? _SearchPane(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              query: _debouncedQuery,
                              entries: entries,
                              onAdd: _addCard,
                            )
                          : _DeckPane(
                              entries: entries,
                              onQuantityChange: _changeQuantity,
                            ),
                    ),
                    if (_tab == 1)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: entries.isEmpty
                                ? null
                                : () => _copyDeckList(entries, validation),
                            icon: const Icon(LucideIcons.listChecks, size: 16),
                            label: const Text('Salin Daftar Deck'),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const PikachuLoader(),
              error: (_, __) => const Center(child: Text('Gagal memuat deck')),
            ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.captionSemibold(
            selected ? colors.onPrimary : context.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _DeckValidityBar extends StatelessWidget {
  const _DeckValidityBar({required this.validation});

  final DeckValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pct = (validation.totalCards / deckMaxCards).clamp(0.0, 1.0);
    final overLimit =
        validation.hasOverCopies || validation.totalCards > deckMaxCards;
    final barColor = validation.isValid
        ? context.appSemantic.success
        : overLimit
        ? colors.error
        : Colors.amber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${validation.totalCards}/$deckMaxCards kartu',
              style: AppTypography.bodySmSemibold(barColor),
            ),
            const Spacer(),
            Text(
              'Pokemon: ${validation.pokemonCount}  Trainer: ${validation.trainerCount}  Energy: ${validation.energyCount}',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: colors.secondary,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
        if (validation.errors.isNotEmpty && validation.totalCards > 0) ...[
          const SizedBox(height: 6),
          for (final e in validation.errors)
            Text(
              deckValidationErrorMessage(e),
              style: AppTypography.caption(colors.error),
            ),
        ],
      ],
    );
  }
}

class _SearchPane extends StatelessWidget {
  const _SearchPane({
    required this.controller,
    required this.onChanged,
    required this.query,
    required this.entries,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String query;
  final List<DeckCardEntry> entries;
  final ValueChanged<CardModel> onAdd;

  Map<String, int> _nameQuantities() {
    final map = <String, int>{};
    for (final e in entries) {
      final baseName = stripCardNameBrackets(e.card.name);
      map[baseName] = (map[baseName] ?? 0) + e.quantity;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final trimmed = query.trim();
        final resultsAsync = trimmed.length >= 2
            ? ref.watch(cardSearchPickerProvider(trimmed))
            : null;
        final nameQuantities = _nameQuantities();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: 'Cari kartu untuk ditambahkan ke deck...',
                prefixIcon: Icon(LucideIcons.search, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            if (resultsAsync == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Ketik nama kartu untuk mencari dan menambahkan ke deck.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ),
              )
            else
              resultsAsync.when(
                data: (results) {
                  if (results.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'Tidak ada kartu yang cocok dengan pencarian.',
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: results.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                    itemBuilder: (context, i) {
                      final card = results[i];
                      final isBasic = isBasicEnergy(card);
                      final baseName = stripCardNameBrackets(card.name);
                      // Aggregate across every print of this name — that's
                      // the real 4-copy limit (same rule as the physical
                      // game: it's per name, not per print).
                      final nameQty = nameQuantities[baseName] ?? 0;
                      // But the badge shown on the tile should only reflect
                      // *this exact print*, so tapping one print doesn't
                      // make every other print of the same name look like
                      // it got added too.
                      final thisPrintQty = entries
                          .where((e) => e.card.id == card.id)
                          .fold<int>(0, (s, e) => s + e.quantity);
                      final atMax = !isBasic && nameQty >= deckMaxCopies;
                      return _DeckSearchCard(
                        card: card,
                        thisPrintQty: thisPrintQty,
                        nameQty: nameQty,
                        maxQty: isBasic ? null : deckMaxCopies,
                        atMax: atMax,
                        onTap: atMax ? null : () => onAdd(card),
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: PikachuLoader(),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'Gagal memuat hasil pencarian',
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DeckSearchCard extends StatelessWidget {
  const _DeckSearchCard({
    required this.card,
    required this.thisPrintQty,
    required this.nameQty,
    required this.maxQty,
    required this.atMax,
    required this.onTap,
  });

  final CardModel card;

  /// How many of *this exact print* are already in the deck — drives the
  /// badge, so only prints you've actually added show one.
  final int thisPrintQty;

  /// Total copies of this card name across every print — the real 4-copy
  /// limit, shared by all prints of the same name.
  final int nameQty;
  final int? maxQty;
  final bool atMax;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Only dim/disable prints that are blocked *and not already the one(s)
    // you added* — otherwise a print you've added 2x would look disabled
    // once the name-wide cap is hit, when really it's just at its share.
    final blockedByOtherPrints = atMax && thisPrintQty == 0;
    return Opacity(
      opacity: blockedByOtherPrints ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: thisPrintQty > 0
                  ? colors.primary.withValues(alpha: 0.5)
                  : context.borderColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CardArt(imageUrl: card.imageUrl),
                  if (thisPrintQty > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$thisPrintQty',
                          style: AppTypography.badge(Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      blockedByOtherPrints
                          ? 'Limit tercapai'
                          : maxQty != null
                          ? '$nameQty/$maxQty'
                          : (thisPrintQty > 0 ? '×$thisPrintQty' : ''),
                      style: AppTypography.caption(
                        blockedByOtherPrints
                            ? colors.error
                            : context.mutedForeground,
                      ),
                    ),
                  ),
                  Text(
                    card.collectorNumber,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckPane extends StatelessWidget {
  const _DeckPane({required this.entries, required this.onQuantityChange});

  final List<DeckCardEntry> entries;
  final void Function(DeckCardEntry entry, int delta) onQuantityChange;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.layers,
        title: 'Belum ada kartu',
        description: 'Cari dan tambahkan kartu dari tab Cari Kartu.',
      );
    }
    final pokemon = entries
        .where((e) => e.category == DeckCategory.pokemon)
        .toList();
    final trainer = entries
        .where((e) => e.category == DeckCategory.trainer)
        .toList();
    final energy = entries
        .where((e) => e.category == DeckCategory.energy)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _DeckCategorySection(
          label: 'Pokemon',
          entries: pokemon,
          onQuantityChange: onQuantityChange,
        ),
        _DeckCategorySection(
          label: 'Trainer',
          entries: trainer,
          onQuantityChange: onQuantityChange,
        ),
        _DeckCategorySection(
          label: 'Energy',
          entries: energy,
          onQuantityChange: onQuantityChange,
        ),
      ],
    );
  }
}

class _DeckCategorySection extends StatelessWidget {
  const _DeckCategorySection({
    required this.label,
    required this.entries,
    required this.onQuantityChange,
  });

  final String label;
  final List<DeckCardEntry> entries;
  final void Function(DeckCardEntry entry, int delta) onQuantityChange;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final count = entries.fold<int>(0, (s, e) => s + e.quantity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${label.toUpperCase()} ($count)',
            style: AppTypography.overline(context.mutedForeground),
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            _DeckCardRow(entry: e, onQuantityChange: onQuantityChange),
        ],
      ),
    );
  }
}

class _DeckCardRow extends StatelessWidget {
  const _DeckCardRow({required this.entry, required this.onQuantityChange});

  final DeckCardEntry entry;
  final void Function(DeckCardEntry entry, int delta) onQuantityChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final basicEnergy = isBasicEnergy(entry.card);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: CardArt(
              imageUrl: entry.card.imageUrl,
              borderRadius: AppRadius.sm,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '${entry.card.expansionCode} ${entry.card.collectorNumber}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          QuantitySelector(
            value: entry.quantity,
            min: 1,
            max: basicEnergy ? 999 : deckMaxCopies,
            onChanged: (v) => onQuantityChange(entry, v - entry.quantity),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => onQuantityChange(entry, -entry.quantity),
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: 14, color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}
