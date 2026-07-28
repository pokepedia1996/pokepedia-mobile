import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/evolution_chain.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/type_icon.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../usecase/expansions_notifier.dart';

/// Ports `app/expansions/[packSlug]/[cardId]/card-detail-page.tsx` +
/// `components/card/card-detail.tsx` (buyer-relevant sections: artwork,
/// Pokemon/Trainer/Energy details from `cards.details`, and the
/// listing/offer tabs).
class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({
    super.key,
    required this.packSlug,
    required this.cardId,
  });

  final String packSlug;
  final int cardId;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _wishlistToggling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _toggleWishlist(bool wishlisted) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _wishlistToggling = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .setWishlisted(widget.cardId, !wishlisted);
    if (!mounted) return;
    setState(() => _wishlistToggling = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardDetailProvider(widget.cardId));
    final listingsAsync = ref.watch(cardListingsProvider(widget.cardId));
    final wishlisted = ref.watch(isWishlistedProvider(widget.cardId));
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: cardAsync.when(
          data: (card) => Text(card?.name ?? 'Kartu'),
          loading: () => const Text('Memuat...'),
          error: (_, __) => const Text('Kartu'),
        ),
        actions: [
          IconButton(
            icon: _wishlistToggling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    wishlisted ? Icons.favorite : Icons.favorite_border,
                    color: wishlisted ? colors.primary : null,
                  ),
            onPressed: _wishlistToggling
                ? null
                : () => _toggleWishlist(wishlisted),
          ),
        ],
      ),
      body: cardAsync.when(
        data: (card) {
          if (card == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Kartu tidak ditemukan',
            );
          }
          return SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: CardArt(
                        imageUrl: card.imageUrl,
                        borderRadius: AppRadius.lg,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: AppTypography.h2(colors.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${card.collectorNumber} · ${card.expansionCode}',
                            style: AppTypography.bodySm(
                              context.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (card.rarity != null)
                                _Chip(text: card.rarity!),
                              _Chip(text: card.category.labelId),
                              if (card.regulationMark != null)
                                _Chip(text: 'Reg. ${card.regulationMark}'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Harga pasar',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                          Text(
                            card.marketPrice != null
                                ? formatRupiah(card.marketPrice!)
                                : 'Rp-',
                            style: AppTypography.h3(colors.onSurface),
                          ),
                          _AddToCollectionSection(cardId: card.id),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _CardDetailsSection(card: card),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tabController,
                  labelColor: colors.primary,
                  unselectedLabelColor: context.mutedForeground,
                  indicatorColor: colors.primary,
                  dividerColor: context.borderColor,
                  tabs: const [
                    Tab(text: 'Listing (WTS)'),
                    Tab(text: 'Penawaran (WTB)'),
                  ],
                ),
                const SizedBox(height: 12),
                listingsAsync.when(
                  data: (listings) {
                    final asks = listings
                        .where((l) => l.side == ListingSide.ask)
                        .toList();
                    final bids = listings
                        .where((l) => l.side == ListingSide.bid)
                        .toList();
                    return AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        final list = _tabController.index == 0 ? asks : bids;
                        if (list.isEmpty) {
                          return const EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Belum ada listing',
                            description:
                                'Jadilah yang pertama menjual atau menawar kartu ini.',
                          );
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: list.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.42,
                              ),
                          itemBuilder: (context, i) =>
                              ListingCard(listing: list[i]),
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Text('Gagal memuat listing'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat kartu',
        ),
      ),
    );
  }
}

/// Ports the `QuantitySelector` + "Tambah/Hapus dari Portofolio" block from
/// `components/card/card-detail.tsx` — local `qty` seeded from the user's
/// current owned count, with the button only shown once `qty` diverges
/// from it (`delta`), same as `useAddToPortfolio`.
class _AddToCollectionSection extends ConsumerStatefulWidget {
  const _AddToCollectionSection({required this.cardId});

  final int cardId;

  @override
  ConsumerState<_AddToCollectionSection> createState() =>
      _AddToCollectionSectionState();
}

class _AddToCollectionSectionState
    extends ConsumerState<_AddToCollectionSection> {
  int _qty = 0;
  int _syncedOwned = 0;
  bool _loading = false;

  Future<void> _submit(int delta) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _loading = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .adjustQuantity(userId: user.id, cardId: widget.cardId, delta: delta);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final abs = delta.abs();
    final message = delta > 0
        ? (abs == 1
              ? 'Kartu ditambahkan ke portofolio'
              : '$abs kartu ditambahkan ke portofolio')
        : (abs == 1
              ? 'Kartu dikurangi dari portofolio'
              : '$abs kartu dikurangi dari portofolio');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final owned =
        ref.watch(ownedQuantityProvider(widget.cardId)).valueOrNull ?? 0;
    if (owned != _syncedOwned) {
      _qty = owned;
      _syncedOwned = owned;
    }
    final delta = _qty - owned;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuantitySelector(
            value: _qty,
            onChanged: (v) => setState(() => _qty = v),
          ),
          if (delta != 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _submit(delta),
                style: ElevatedButton.styleFrom(
                  backgroundColor: delta > 0
                      ? context.appSemantic.success
                      : context.appColors.error,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        delta > 0
                            ? 'Tambah ke Portofolio'
                            : 'Hapus dari Portofolio',
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

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
/// `components/card/card-detail.tsx`, sourced from `cards.details`.
class _CardDetailsSection extends StatelessWidget {
  const _CardDetailsSection({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    switch (card.category) {
      case CardCategory.pokemon:
        return _PokemonDetails(card: card);
      case CardCategory.trainer:
        return _InfoCard(
          title: 'Trainer',
          child: Text(
            card.details.trainerSubtype?.labelId ?? 'Trainer',
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
        );
      case CardCategory.energy:
        final type = card.details.energyType;
        return _InfoCard(
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

class _PokemonDetails extends ConsumerStatefulWidget {
  const _PokemonDetails({required this.card});

  final CardModel card;

  @override
  ConsumerState<_PokemonDetails> createState() => _PokemonDetailsState();
}

class _PokemonDetailsState extends ConsumerState<_PokemonDetails> {
  bool _expanded = false;
  final Map<int, int> _selectedOverride = {};

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = widget.card;
    final d = card.details;
    return _InfoCard(
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
                _Chip(text: d.evolutionStage!.labelId),
            ],
          ),
          if (d.attacks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Serangan',
              style: AppTypography.captionSemibold(context.mutedForeground),
            ),
            const SizedBox(height: 8),
            for (final attack in d.attacks) _AttackRow(attack: attack),
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
            _EvolutionSection(
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
            _PokedexSection(details: d),
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
class _EvolutionSection extends ConsumerWidget {
  const _EvolutionSection({
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
      evolutionPoolProvider((card.name, card.details.evolvesFrom)),
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
                    _EvolutionStageChip(
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
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _EvolutionStageChip extends StatelessWidget {
  const _EvolutionStageChip({
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

    // `Wrap` (the parent in `_EvolutionSection`) only supports plain
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
class _PokedexSection extends StatelessWidget {
  const _PokedexSection({required this.details});

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
              child: _StatBox(
                label: 'No.',
                value: details.pokedexNumber != null
                    ? '#${details.pokedexNumber}'
                    : '-',
              ),
            ),
            if (details.pokedexHeight != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Tinggi',
                  value: '${details.pokedexHeight} m',
                ),
              ),
            ],
            if (details.pokedexWeight != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
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

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

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

class _AttackRow extends StatelessWidget {
  const _AttackRow({required this.attack});

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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

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
