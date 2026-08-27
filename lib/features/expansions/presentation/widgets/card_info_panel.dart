import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/pokemon_type.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../../shared/widgets/type_icon.dart';
import 'card_details_section.dart';

/// Ports the right-hand info column of `components/card/card-detail.tsx` —
/// everything the web renders between the card's badges and its illustrator
/// meta rows, in the same order and separated by the same hairline rules.
/// Unlike the old collapsible "Info Pokemon" card this is always open, as
/// on the web.
class CardInfoPanel extends StatefulWidget {
  const CardInfoPanel({super.key, required this.card});

  final CardModel card;

  @override
  State<CardInfoPanel> createState() => _CardInfoPanelState();
}

class _CardInfoPanelState extends State<CardInfoPanel> {
  final Map<int, int> _evolutionOverride = {};

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final d = card.details;
    final isPokemon = card.category == CardCategory.pokemon;
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CardLanguageBadge(language: card.language),
            const SizedBox(width: 6),
            if (_typeFamilyLabel(card) != null)
              _TypeFamilyChip(label: _typeFamilyLabel(card)!, card: card),
            const Spacer(),
            if (isPokemon) ...[
              Text(
                'HP ${d.hp ?? '-'}',
                style: AppTypography.h3(colors.primary),
              ),
              const SizedBox(width: 6),
              for (final type in d.pokemonTypes) ...[
                TypeIcon(type: type, size: 20),
                const SizedBox(width: 3),
              ],
            ],
          ],
        ),
        if (isPokemon && d.evolutionStage != null && d.evolvesFrom != null) ...[
          const _Rule(),
          Text.rich(
            TextSpan(
              text: 'Evolusi dari ',
              style: AppTypography.bodySm(context.mutedForeground),
              children: [
                TextSpan(
                  text: d.evolvesFrom!,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ],
            ),
          ),
        ],
        if (d.ability != null) ...[
          const _Rule(),
          _Block(
            title: 'Ability',
            child: _AbilityRow(ability: d.ability!),
          ),
        ],
        if (d.attacks.isNotEmpty) ...[
          const _Rule(),
          _Block(
            title: 'Serangan',
            child: Column(
              children: [
                for (final attack in d.attacks) _AttackTile(attack: attack),
              ],
            ),
          ),
        ],
        if (!isPokemon && d.effect != null && d.effect!.isNotEmpty) ...[
          const _Rule(),
          _Block(
            title: 'Efek',
            child: _MutedBox(
              child: Text(
                d.effect!,
                style: AppTypography.bodySm(colors.onSurface),
              ),
            ),
          ),
        ],
        if (isPokemon) ...[
          const _Rule(),
          // `CrossAxisAlignment.stretch` asks children for an unbounded height,
          // which is exactly what a ListView hands down — the raw Row throws
          // "BoxConstraints forces an infinite height" and takes the rest of
          // this Column (evolution, Pokedex) down with it. IntrinsicHeight
          // bounds the Row to its tallest child, so the stat boxes still share
          // one height.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InfoStatBox(
                    label: 'Kelemahan',
                    child: d.weakness == null
                        ? const _Dash()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TypeIcon(type: d.weakness!.type, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                d.weakness!.value,
                                style: AppTypography.bodySmSemibold(
                                  colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InfoStatBox(
                    label: 'Resistansi',
                    child: d.resistance == null
                        ? const _Dash()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TypeIcon(type: d.resistance!.type, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                d.resistance!.value,
                                style: AppTypography.bodySmSemibold(
                                  colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InfoStatBox(
                    label: 'Mundur',
                    child: d.retreatCost == null || d.retreatCost == 0
                        ? const _Dash()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < d.retreatCost!; i++)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 1),
                                  child: TypeIcon(
                                    type: PokemonType.colorless,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isPokemon) ...[
          const _Rule(),
          EvolutionSection(
            card: card,
            selectedOverride: _evolutionOverride,
            onCycle: (stageIdx, current, length, direction) {
              setState(() {
                _evolutionOverride[stageIdx] =
                    (current + direction + length) % length;
              });
            },
          ),
          const _Rule(),
          _Block(
            title: 'Pokédex',
            // `CrossAxisAlignment.stretch` asks children for an unbounded height,
            // which is exactly what a ListView hands down — the raw Row throws
            // "BoxConstraints forces an infinite height" and takes the rest of
            // this Column (evolution, Pokedex) down with it. IntrinsicHeight
            // bounds the Row to its tallest child, so the stat boxes still share
            // one height.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: InfoStatBox(
                      label: 'No.',
                      child: _StatValue(
                        d.pokedexNumber != null ? '#${d.pokedexNumber}' : '-',
                      ),
                    ),
                  ),
                  if (d.pokedexHeight != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: InfoStatBox(
                        label: 'Tinggi',
                        child: _StatValue('${d.pokedexHeight} m'),
                      ),
                    ),
                  ],
                  if (d.pokedexWeight != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: InfoStatBox(
                        label: 'Berat',
                        child: _StatValue('${d.pokedexWeight} kg'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const _Rule(),
        if (card.illustrator != null)
          _MetaRow(label: 'Ilustrator', value: card.illustrator!),
        if (card.rarity != null)
          _MetaRow(label: 'Kelangkaan', value: card.rarity!),
        if (card.regulationMark != null)
          _MetaRow(label: 'Regulasi', value: card.regulationMark!),
      ],
    );
  }

  /// The single "what kind of card is this" chip web puts next to the
  /// language badge: the Trainer subtype, "Energy", or the evolution stage.
  String? _typeFamilyLabel(CardModel card) {
    switch (card.category) {
      case CardCategory.trainer:
        return card.details.trainerSubtype?.labelId;
      case CardCategory.energy:
        return 'Energy';
      case CardCategory.pokemon:
        return card.details.evolutionStage?.labelId;
    }
  }
}

class _TypeFamilyChip extends StatelessWidget {
  const _TypeFamilyChip({required this.label, required this.card});

  final String label;
  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final semantic = context.appSemantic;
    final color = switch (card.category) {
      CardCategory.trainer => semantic.bid,
      CardCategory.energy => semantic.gold,
      CardCategory.pokemon => context.mutedForeground,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(label, style: AppTypography.badge(color)),
    );
  }
}

/// A titled section, matching web's `<p class="typo-body-sm font-semibold">`
/// heading above each block.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTypography.bodySmSemibold(context.appColors.onSurface),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _AbilityRow extends StatelessWidget {
  const _AbilityRow({required this.ability});

  final AbilityModel ability;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _MutedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'Ability',
                  style: AppTypography.badge(Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ability.name,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
            ],
          ),
          if (ability.description != null &&
              ability.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ability.description!,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttackTile extends StatelessWidget {
  const _AttackTile({required this.attack});

  final AttackModel attack;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _MutedBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (attack.cost.isEmpty)
                  Icon(
                    Icons.blur_circular,
                    size: 18,
                    color: context.mutedForeground,
                  )
                else
                  for (final type in attack.cost)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: TypeIcon(type: type, size: 18),
                    ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attack.name.isEmpty ? 'Serangan' : attack.name,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ),
                if (attack.damage.isNotEmpty)
                  Text(
                    attack.damage,
                    style: AppTypography.h3(colors.onSurface),
                  ),
              ],
            ),
            if (attack.effect != null && attack.effect!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                attack.effect!,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bordered `bg-muted` block web wraps abilities, attacks and effects in.
class _MutedBox extends StatelessWidget {
  const _MutedBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.5),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: child,
    );
  }
}

/// Ports web's `StatBox` — an uppercase caption over a centered value.
class InfoStatBox extends StatelessWidget {
  const InfoStatBox({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.5),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.overline(context.mutedForeground),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppTypography.bodySmSemibold(context.appColors.onSurface),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) {
    return Text('-', style: AppTypography.bodySm(context.mutedForeground));
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.bodySm(context.appColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline `<Divider />` web puts between every info block.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: context.borderColor),
    );
  }
}
