import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/card_ownership_controller.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_market_price.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../../home/repository/models/portfolio_value.dart';
import '../../../home/usecase/portfolio_value_notifier.dart';
import '../../../portfolio/presentation/widgets/portfolio_picker_sheet.dart';
import '../../../portfolio/usecase/portfolio_notifier.dart';
import '../../usecase/expansions_notifier.dart';

/// How long a burst of taps on the stepper is allowed to settle before it is
/// written. A stepper is tapped, not submitted, so five taps up should cost
/// one write rather than five.
const _writeDelay = Duration(milliseconds: 700);

/// "Menambah ke: Utama · Total: Rp0" — the panel that owns adding this card
/// to a portfolio, in place of the bare counter that used to sit under the
/// artwork.
///
/// Which portfolio is [selectedPortfolioProvider], the same one Beranda's
/// header values and the Koleksi page lists: switching it here switches it
/// everywhere, which is the point — "the portfolio I'm working in" is one
/// idea, not one per screen.
class AddToPortfolioPanel extends ConsumerStatefulWidget {
  const AddToPortfolioPanel({super.key, required this.card});

  final CardModel card;

  @override
  ConsumerState<AddToPortfolioPanel> createState() =>
      _AddToPortfolioPanelState();
}

class _AddToPortfolioPanelState extends ConsumerState<AddToPortfolioPanel> {
  /// What the stepper reads. Null until the server's count has arrived —
  /// showing 0 before then invites a tap that would write the wrong delta.
  int? _qty;

  /// The count the server last confirmed, which the delta is measured from.
  int _saved = 0;

  /// The target [_saved] belongs to, so switching portfolios re-seeds rather
  /// than carrying the previous shelf's count over.
  PortfolioTarget? _seededFor;

  Timer? _timer;
  bool _saving = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The card's count in whichever portfolio is selected: the collection's
  /// own for "Utama", the list's own quantity otherwise.
  int? _serverQuantity(PortfolioTarget target) {
    if (target.isPrimary) {
      return ref.watch(ownedQuantityProvider(widget.card.id)).valueOrNull;
    }
    final cards = ref.watch(listCardsProvider(target.listId!)).valueOrNull;
    if (cards == null) return null;
    for (final card in cards) {
      if (card.id == widget.card.id) return card.owned;
    }
    return 0;
  }

  void _bump(int next, PortfolioTarget target) {
    // Asked for up front rather than after the debounce: counting up and
    // then being bounced to the login page reads as the taps being thrown
    // away, which is exactly what would have happened.
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _qty = next);
    _timer?.cancel();
    _timer = Timer(_writeDelay, () => _write(target));
  }

  Future<void> _write(PortfolioTarget target) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final wanted = _qty;
    if (wanted == null || wanted == _saved) return;

    setState(() => _saving = true);
    final controller = ref.read(cardOwnershipControllerProvider);
    // A list holds its own copies at its own quantity, so it is set rather
    // than nudged; the collection only offers a delta.
    final error = target.isPrimary
        ? await controller.adjustQuantity(
            userId: user.id,
            cardId: widget.card.id,
            delta: wanted - _saved,
          )
        : await controller.setListCardQuantity(
            listId: target.listId!,
            cardId: widget.card.id,
            quantity: wanted,
          );
    if (!mounted) return;

    setState(() {
      _saving = false;
      if (error == null) _saved = wanted;
    });

    if (error != null) {
      // Back to what the server actually holds, rather than leaving a
      // number on screen that nothing stands behind.
      setState(() => _qty = _saved);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Watched, not read on demand: a provider first touched inside the
    // debounce timer would still be loading when the write asks who is
    // signed in, and the write would be dropped.
    ref.watch(authProvider);
    final target = ref.watch(selectedPortfolioProvider);
    final server = _serverQuantity(target);

    // Seed from the server once per target, and re-seed whenever it moves
    // underneath us — an add from the scanner, or the same card edited on
    // the collection page.
    final writePending = _saving || (_timer?.isActive ?? false);
    if (server != null) {
      // While a write is on its way the local number is the truthful one:
      // the provider still holds the count from before it.
      final switchedShelf = _seededFor != target;
      if (switchedShelf || (!writePending && server != _saved)) {
        _seededFor = target;
        _saved = server;
        _qty = server;
      }
    }

    final price = ref
        .watch(cardMarketPriceProvider(widget.card.id))
        .valueOrNull;
    final qty = _qty ?? 0;
    final total = (price?.price ?? 0) * qty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Flexible(
                  child: _TargetButton(
                    target: target,
                    onTap: () => showPortfolioPicker(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Total: ${price == null ? 'Rp–' : formatRupiah(total)}',
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    variantLabel(widget.card.variant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                if (server == null)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  QuantitySelector(
                    value: qty,
                    onChanged: (value) => _bump(value, target),
                  ),
                const SizedBox(width: 8),
                _PriceColumn(price: price),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `listings.variant_key` / `cards.variant` as a person would say it.
String variantLabel(String variant) {
  final cleaned = variant.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) return 'Normal';
  return cleaned
      .split(' ')
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}

/// "Menambah ke: Utama ⌄" — tapping opens the same picker Beranda uses.
class _TargetButton extends StatelessWidget {
  const _TargetButton({required this.target, required this.onTap});

  final PortfolioTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Menambah ke: ',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          Flexible(
            child: Text(
              target.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.primary),
            ),
          ),
          Icon(LucideIcons.chevronDown, size: 15, color: colors.primary),
        ],
      ),
    );
  }
}

/// The market price, with the week's move under it — the same figure and the
/// same rule the catalog tiles use: only a confirmed price has a move worth
/// stating.
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({this.price});

  final CardMarketPrice? price;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final value = price;
    if (value == null) {
      return Text('Rp–', style: AppTypography.bodySmSemibold(colors.onSurface));
    }

    final then = value.price7dAgo;
    final movable =
        value.source == CardPriceSource.confirmed && then != null && then > 0;
    final delta = movable ? value.price - then : 0;
    final pct = movable ? delta / then * 100 : 0.0;
    final tone = delta > 0
        ? context.appSemantic.success
        : delta < 0
        ? colors.error
        : context.mutedForeground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatRupiah(value.price),
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        if (movable && delta != 0)
          Text(
            '${delta > 0 ? '+' : '-'}${formatRupiah(delta.abs())} '
            '(${pct.abs().toStringAsFixed(1)}%)',
            style: AppTypography.badge(
              tone,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
      ],
    );
  }
}
