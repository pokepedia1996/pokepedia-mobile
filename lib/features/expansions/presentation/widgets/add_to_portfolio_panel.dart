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

/// How long the green tick sits on the button after a write lands, before
/// the stepper goes back to normal.
const _doneDelay = Duration(milliseconds: 900);

/// Which of the two buttons a tap came from — what says where the working
/// and finished states are drawn.
enum _Step { minus, plus }

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

  /// A write has landed and the provider hasn't caught up yet.
  ///
  /// Between the two, the provider is still reporting the count from *before*
  /// the write — re-seeding from it there would snap the number back to what
  /// the user just changed it from, and then forward again a frame later.
  /// Cleared the moment the server agrees with what was written.
  bool _awaitingRefresh = false;

  /// The button a write is running from. Non-null locks both of them: a
  /// second tap would measure its delta from a [_saved] the server hasn't
  /// confirmed yet.
  _Step? _busy;

  /// The button showing the tick. Cleared by [_doneTimer].
  _Step? _done;
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
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

  /// A tap on one of the signs: the count moves, both buttons lock, and the
  /// write goes out immediately.
  ///
  /// No debounce. A stepper that waits before writing has to look idle while
  /// it does, and the wait is exactly when the reader wonders whether the tap
  /// registered — so the button that was pressed takes the working state on
  /// the same frame, and a burst of taps costs a write each rather than
  /// costing the feedback.
  void _bump(_Step step, PortfolioTarget target) {
    if (_busy != null) return;
    // Asked for up front: counting up and then being bounced to the login
    // page reads as the tap being thrown away, which is what would happen.
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }

    final current = _qty ?? 0;
    final next = step == _Step.plus ? current + 1 : current - 1;
    if (next < 0 || next > 99) return;

    _doneTimer?.cancel();
    setState(() {
      _qty = next;
      _busy = step;
      _done = null;
    });
    _write(target, step);
  }

  Future<void> _write(PortfolioTarget target, _Step step) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final wanted = _qty;
    if (wanted == null) return;

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
      _busy = null;
      if (error == null) {
        _saved = wanted;
        _awaitingRefresh = true;
        // The tick lands on the button that was pressed, where the reader
        // is already looking.
        _done = step;
      } else {
        // Back to what the server actually holds, rather than leaving a
        // number on screen that nothing stands behind.
        _qty = _saved;
      }
    });

    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
      return;
    }

    _doneTimer = Timer(_doneDelay, () {
      if (mounted) setState(() => _done = null);
    });
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
    if (server != null) {
      final switchedShelf = _seededFor != target;
      if (server == _saved) _awaitingRefresh = false;
      // While a write is on its way — or its refetch hasn't landed — the
      // local number is the truthful one.
      final pending = _busy != null || _awaitingRefresh;
      if (switchedShelf || (!pending && server != _saved)) {
        _seededFor = target;
        _saved = server;
        _qty = server;
        _awaitingRefresh = false;
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: _TargetButton(
                    target: target,
                    onTap: () => showPortfolioPicker(context, ref),
                  ),
                ),

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
                // The stepper keeps its shape while the count is still
                // arriving — a control that appears late moves everything
                // beside it.
                _PortfolioStepper(
                  value: qty,
                  ready: server != null,
                  busy: _busy,
                  done: _done,
                  onStep: (step) => _bump(step, target),
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

/// The stepper this panel owns, rather than the shared [QuantitySelector].
///
/// The difference is where the write shows: each sign carries its own state,
/// so the button that was pressed is the one that reports back. A spinner
/// beside the control said "something is happening somewhere"; this says
/// "this tap, here".
class _PortfolioStepper extends StatelessWidget {
  const _PortfolioStepper({
    required this.value,
    required this.ready,
    required this.busy,
    required this.done,
    required this.onStep,
  });

  final int value;

  /// False until the server's count lands — the signs are inert, but the
  /// control is still drawn so nothing shifts when it arrives.
  final bool ready;

  final _Step? busy;
  final _Step? done;
  final ValueChanged<_Step> onStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Both signs go dead the moment either is pressed: the next delta is
    // measured from a count the server hasn't confirmed yet.
    final locked = !ready || busy != null;

    _Phase phaseOf(_Step step) {
      if (busy == step) return _Phase.working;
      if (done == step) return _Phase.done;
      return _Phase.idle;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: LucideIcons.minus,
          phase: phaseOf(_Step.minus),
          onTap: locked || value <= 0 ? null : () => onStep(_Step.minus),
        ),
        const SizedBox(width: 6),
        Container(
          width: 48,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            // The count slides rather than blinks, so a run of taps reads as
            // one number moving.
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              ready ? '$value' : '–',
              key: ValueKey(ready ? value : null),
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _StepButton(
          icon: LucideIcons.plus,
          phase: phaseOf(_Step.plus),
          onTap: locked || value >= 99 ? null : () => onStep(_Step.plus),
        ),
      ],
    );
  }
}

/// What one sign is doing.
enum _Phase { idle, working, done }

/// One sign of the stepper, and the three states it can be in.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.phase,
    required this.onTap,
  });

  final IconData icon;
  final _Phase phase;
  final VoidCallback? onTap;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton>
    with SingleTickerProviderStateMixin {
  /// The working state's breath. Not a spinner: a spinner is a thing to
  /// watch, and this is a wait measured in a couple of hundred milliseconds
  /// — the button glowing in the colour it is about to confirm in reads as
  /// the same gesture continuing.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_StepButton old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) _syncPulse();
  }

  void _syncPulse() {
    if (widget.phase == _Phase.working) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final success = context.appSemantic.success;
    final radius = BorderRadius.circular(AppRadius.md);
    final working = widget.phase == _Phase.working;
    final done = widget.phase == _Phase.done;
    // A bound reached, or the other button holding the lock.
    final dimmed = widget.onTap == null && !working && !done;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: radius,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final fill = done
              ? success
              : working
              // Deepening and easing back, in the colour the tick lands in.
              ? Color.lerp(
                  success.withValues(alpha: 0.20),
                  success.withValues(alpha: 0.62),
                  Curves.easeInOut.transform(_pulse.value),
                )!
              : colors.secondary;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(
                color: working || done ? success : context.borderColor,
              ),
              borderRadius: radius,
            ),
            child: Opacity(opacity: dimmed ? 0.3 : 1, child: child),
          );
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: done
              ? const Icon(
                  LucideIcons.check,
                  key: ValueKey('done'),
                  size: 16,
                  color: Colors.white,
                )
              : Icon(
                  widget.icon,
                  key: const ValueKey('sign'),
                  size: 14,
                  color: working ? Colors.white : context.mutedForeground,
                ),
        ),
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
