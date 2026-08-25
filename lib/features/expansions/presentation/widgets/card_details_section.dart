import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/pokemon_type.dart';
import '../../../../shared/utils/evolution_chain.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../../shared/widgets/type_icon.dart';
import '../../usecase/expansions_notifier.dart';

/// A small rounded label pill — rarity, category, evolution stage, etc.
class CardInfoChip extends StatelessWidget {
  const CardInfoChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(text, style: AppTypography.captionSemibold(colors.onSurface)),
    );
  }
}

/// Ports the Pokemon/Trainer/Energy fact panels from
/// `components/card/card-detail.tsx`, sourced from `cards.details`. Shared
/// between the encyclopedia card page and the per-seller market listing
/// page (mirroring how `StoreCardDetailView` backs both on the web), so
/// it's placed under `expansions` (which owns [evolutionPoolProvider])
/// rather than `shared/widgets`.
class CardDetailsSection extends StatelessWidget {
  const CardDetailsSection({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    switch (card.category) {
      case CardCategory.pokemon:
        return PokemonDetailsCard(card: card);
      case CardCategory.trainer:
        return InfoCard(
          title: 'Trainer',
          child: Text(
            card.details.trainerSubtype?.labelId ?? 'Trainer',
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
        );
      case CardCategory.energy:
        final type = card.details.energyType;
        return InfoCard(
          title: 'Energy',
          child: Row(
            children: [
              if (type != null) ...[
                TypeIcon(type: type, size: 22),
                const SizedBox(width: 8),
              ],
              Text(
                type?.labelId ?? 'Energy',
                style: AppTypography.bodySm(context.appColors.onSurface),
              ),
            ],
          ),
        );
    }
  }
}

class PokemonDetailsCard extends ConsumerStatefulWidget {
  const PokemonDetailsCard({super.key, required this.card});

  final CardModel card;

  @override
  ConsumerState<PokemonDetailsCard> createState() => _PokemonDetailsCardState();
}

class _PokemonDetailsCardState extends ConsumerState<PokemonDetailsCard> {
  bool _expanded = false;
  final Map<int, int> _selectedOverride = {};

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = widget.card;
    final d = card.details;
    return InfoCard(
      title: 'Info Pokemon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (d.hp != null) ...[
                Text(
                  'HP ${d.hp}',
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                const SizedBox(width: 10),
              ],
              for (final t in d.pokemonTypes) ...[
                TypeIcon(type: t, size: 20),
                const SizedBox(width: 4),
              ],
              const Spacer(),
              if (d.evolutionStage != null)
                CardInfoChip(text: d.evolutionStage!.labelId),
            ],
          ),
          if (d.attacks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Serangan',
              style: AppTypography.captionSemibold(context.mutedForeground),
            ),
            const SizedBox(height: 8),
            for (final attack in d.attacks) AttackRow(attack: attack),
          ],
          if (d.weakness != null || d.retreatCost != null) ...[
            const SizedBox(height: 12),
            Divider(color: context.borderColor),
            const SizedBox(height: 10),
            Row(
              children: [
                if (d.weakness != null) ...[
                  Text(
                    'Kelemahan: ',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  TypeIcon(type: d.weakness!.type, size: 16),
                  const SizedBox(width: 3),
                  Text(
                    d.weakness!.value,
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                  const SizedBox(width: 16),
                ],
                if (d.retreatCost != null) ...[
                  Text(
                    'Mundur: ',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  Text(
                    '${d.retreatCost}',
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (_expanded) ...[
            Divider(color: context.borderColor),
            const SizedBox(height: 10),
            EvolutionSection(
              card: card,
              selectedOverride: _selectedOverride,
              onCycle: (stageIdx, current, length, direction) {
                setState(() {
                  _selectedOverride[stageIdx] =
                      (current + direction + length) % length;
                });
              },
            ),
            const SizedBox(height: 14),
            Divider(color: context.borderColor),
            const SizedBox(height: 10),
            PokedexStatsSection(details: d),
          ],
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 16,
              ),
              label: Text(
                _expanded
                    ? 'Tampilkan lebih sedikit'
                    : 'Tampilkan lebih banyak',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ports `EvolutionChainSection` from `components/card/card-detail.tsx`.
class EvolutionSection extends ConsumerWidget {
  const EvolutionSection({
    super.key,
    required this.card,
    required this.selectedOverride,
    required this.onCycle,
  });

  final CardModel card;
  final Map<int, int> selectedOverride;
  final void Function(int stageIdx, int current, int length, int direction)
  onCycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (card.category != CardCategory.pokemon) return const SizedBox.shrink();
    final poolAsync = ref.watch(
      evolutionPoolProvider((
        name: card.name,
        evolvesFrom: card.details.evolvesFrom,
      )),
    );

    return poolAsync.when(
      data: (pool) {
        final stages = buildEvolutionStages(card, pool);
        if (stages == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evolusi',
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                direction: Axis.vertical,
                spacing: 4,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < stages.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 20,
                        color: context.mutedForeground.withValues(alpha: 0.5),
                      ),
                    EvolutionStageChip(
                      stageIndex: i,
                      stage: stages[i],
                      card: card,
                      selectedOverride: selectedOverride,
                      onCycle: onCycle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: PikachuLoader(size: 96),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class EvolutionStageChip extends StatelessWidget {
  const EvolutionStageChip({
    super.key,
    required this.stageIndex,
    required this.stage,
    required this.card,
    required this.selectedOverride,
    required this.onCycle,
  });

  final int stageIndex;
  final EvolutionStageGroup stage;
  final CardModel card;
  final Map<int, int> selectedOverride;
  final void Function(int stageIdx, int current, int length, int direction)
  onCycle;

  int get _defaultIndex {
    var idx = stage.cards.indexWhere((c) => c.cardId == card.id);
    if (idx < 0) idx = stage.cards.indexWhere((c) => c.name == card.name);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectedIdx = selectedOverride[stageIndex] ?? _defaultIndex;
    final selected = stage.cards[selectedIdx];
    final isCurrent = selected.cardId == card.id || selected.name == card.name;
    final hasVariants = stage.cards.length > 1;
    final spriteUrl = pokemonSpriteUrl(selected.pokedexNumber);

    // `Wrap` (the parent in `EvolutionSection`) only supports plain
    // children — `Expanded`/`Flexible` require a `Flex` (Row/Column)
    // ancestor. In debug this is caught by an assert with a clear error
    // message; in release the assert is stripped and it instead throws a
    // bare `WrapParentData is not a subtype of FlexParentData` type-cast
    // error at the render layer, which renders as a blank gray
    // `ErrorWidget` box — this must stay a plain `Row`, not `Expanded`.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasVariants)
          InkWell(
            onTap: () =>
                onCycle(stageIndex, selectedIdx, stage.cards.length, -1),
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_left,
                size: 16,
                color: context.mutedForeground,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isCurrent ? colors.secondary : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: isCurrent ? null : Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spriteUrl != null) ...[
                Image.network(
                  spriteUrl,
                  width: 40,
                  height: 40,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                selected.name,
                style: AppTypography.bodySmSemibold(
                  isCurrent ? colors.onSurface : context.mutedForeground,
                ),
              ),
              if (hasVariants) ...[
                const SizedBox(width: 4),
                Text(
                  '${selectedIdx + 1}/${stage.cards.length}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ],
          ),
        ),
        if (hasVariants)
          InkWell(
            onTap: () =>
                onCycle(stageIndex, selectedIdx, stage.cards.length, 1),
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: context.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }
}

/// Ports the "Pokédex" stat-box row from `components/card/card-detail.tsx`.
class PokedexStatsSection extends StatelessWidget {
  const PokedexStatsSection({super.key, required this.details});

  final CardDetails details;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pokédex', style: AppTypography.bodySmSemibold(colors.onSurface)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatBox(
                label: 'No.',
                value: details.pokedexNumber != null
                    ? '#${details.pokedexNumber}'
                    : '-',
              ),
            ),
            if (details.pokedexHeight != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: StatBox(
                  label: 'Tinggi',
                  value: '${details.pokedexHeight} m',
                ),
              ),
            ],
            if (details.pokedexWeight != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: StatBox(
                  label: 'Berat',
                  value: '${details.pokedexWeight} kg',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context.mutedForeground)),
          Text(value, style: AppTypography.bodySmSemibold(colors.onSurface)),
        ],
      ),
    );
  }
}

class AttackRow extends StatelessWidget {
  const AttackRow({super.key, required this.attack});

  final AttackModel attack;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final t in attack.cost) ...[
                TypeIcon(type: t, size: 16),
                const SizedBox(width: 2),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  attack.name,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              Text(
                attack.damage,
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ],
          ),
          if (attack.effect != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                attack.effect!,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
