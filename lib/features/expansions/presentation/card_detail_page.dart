import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/type_icon.dart';
import '../usecase/expansions_notifier.dart';

/// Ports `app/expansions/[packSlug]/[cardId]/card-detail-page.tsx` +
/// `components/card/card-detail.tsx` (buyer-relevant sections: artwork,
/// Pokemon/Trainer/Energy details from `cards.details`, and the
/// listing/offer tabs).
class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({super.key, required this.packSlug, required this.cardId});

  final String packSlug;
  final int cardId;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _wishlisted = false;

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

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardDetailProvider(widget.cardId));
    final listingsAsync = ref.watch(cardListingsProvider(widget.cardId));
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
            icon: Icon(
              _wishlisted ? Icons.favorite : Icons.favorite_border,
              color: _wishlisted ? colors.primary : null,
            ),
            onPressed: () => setState(() => _wishlisted = !_wishlisted),
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
                    const SizedBox(width: 130, child: CardArt(borderRadius: AppRadius.lg)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.name, style: AppTypography.h2(colors.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            '${card.collectorNumber} · ${card.expansionCode}',
                            style: AppTypography.bodySm(context.mutedForeground),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (card.rarity != null) _Chip(text: card.rarity!),
                              _Chip(text: card.category.labelId),
                              if (card.regulationMark != null)
                                _Chip(text: 'Reg. ${card.regulationMark}'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Harga pasar', style: AppTypography.caption(context.mutedForeground)),
                          Text(
                            card.marketPrice != null ? formatRupiah(card.marketPrice!) : 'Rp-',
                            style: AppTypography.h3(colors.onSurface),
                          ),
                          if (card.owned > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.check_circle, size: 14, color: context.appSemantic.success),
                                const SizedBox(width: 4),
                                Text(
                                  'Dimiliki ×${card.owned}',
                                  style: AppTypography.captionSemibold(context.appSemantic.success),
                                ),
                              ],
                            ),
                          ],
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
                    final asks = listings.where((l) => l.side == ListingSide.ask).toList();
                    final bids = listings.where((l) => l.side == ListingSide.bid).toList();
                    return AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        final list = _tabController.index == 0 ? asks : bids;
                        if (list.isEmpty) {
                          return const EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Belum ada listing',
                            description: 'Jadilah yang pertama menjual atau menawar kartu ini.',
                          );
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: list.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.6,
                          ),
                          itemBuilder: (context, i) => ListingCard(listing: list[i], onTap: () {}),
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
        error: (_, __) => const EmptyState(icon: Icons.error_outline, title: 'Gagal memuat kartu'),
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

class _PokemonDetails extends StatelessWidget {
  const _PokemonDetails({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final d = card.details;
    return _InfoCard(
      title: 'Info Pokémon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (d.hp != null) ...[
                Text('HP ${d.hp}', style: AppTypography.bodySemibold(colors.onSurface)),
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
          if (d.evolvesFrom != null) ...[
            const SizedBox(height: 6),
            Text(
              'Berevolusi dari ${d.evolvesFrom}',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
          if (d.attacks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Serangan', style: AppTypography.captionSemibold(context.mutedForeground)),
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
                  Text('Lemah: ', style: AppTypography.caption(context.mutedForeground)),
                  TypeIcon(type: d.weakness!.type, size: 16),
                  const SizedBox(width: 3),
                  Text(d.weakness!.value, style: AppTypography.captionSemibold(colors.onSurface)),
                  const SizedBox(width: 16),
                ],
                if (d.retreatCost != null) ...[
                  Text('Mundur: ', style: AppTypography.caption(context.mutedForeground)),
                  Text('${d.retreatCost}', style: AppTypography.captionSemibold(colors.onSurface)),
                ],
              ],
            ),
          ],
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
                child: Text(attack.name, style: AppTypography.bodySmSemibold(colors.onSurface)),
              ),
              Text(attack.damage, style: AppTypography.bodySemibold(colors.onSurface)),
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
          Text(title, style: AppTypography.captionSemibold(context.mutedForeground)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
