import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../home/repository/models/portfolio_value.dart';
import '../../../home/usecase/portfolio_value_notifier.dart';
import '../../../portfolio/presentation/widgets/portfolio_picker_sheet.dart';
import '../../repository/models/market_models.dart';
import '../../usecase/expansions_notifier.dart';
import 'condition_toggle_picker.dart';

/// How long the green tick sits on the button after a write lands, before
/// the stepper goes back to normal.
const _doneDelay = Duration(milliseconds: 900);

/// How long a picked chip shows as picked before the picker folds away.
const _closeAfterPick = Duration(milliseconds: 120);

/// Which of the two buttons a tap came from — what says where the working
/// and finished states are drawn.
enum _Step { minus, plus }

/// "Menambah ke: Utama · Total: Rp0" — the panel that owns adding this card
/// to a portfolio, one condition at a time.
///
/// Which portfolio is [selectedPortfolioProvider], the same one Beranda's
/// header values and the Koleksi page lists: switching it here switches it
/// everywhere, which is the point — "the portfolio I'm working in" is one
/// idea, not one per screen.
///
/// A card is counted per condition: the row's stepper and price are the
/// picked condition's, the total is every condition held, and the picker
/// under the row shows how many of each are already there.
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

  /// Which condition the stepper counts. Null until the portfolio's counts
  /// have arrived, then the one held most (§3.1) — and again on switching
  /// portfolio.
  CardCondition? _condition;

  /// The portfolio [_condition] was chosen for.
  PortfolioTarget? _conditionFor;

  /// The shelf and condition [_saved] belongs to, so switching either
  /// re-seeds rather than carrying the previous count over.
  ({PortfolioTarget target, CardCondition condition})? _seededFor;

  /// A write has landed and the provider hasn't caught up yet.
  ///
  /// Between the two, the provider is still reporting the count from *before*
  /// the write — re-seeding from it there would snap the number back to what
  /// the user just changed it from, and then forward again a frame later.
  /// Cleared the moment the server agrees with what was written.
  bool _awaitingRefresh = false;

  /// The button a write is running from. Non-null locks both of them — and
  /// the conditions: a second tap would measure its delta from a [_saved]
  /// the server hasn't confirmed yet, and a switch would count the landing
  /// write against the wrong condition.
  _Step? _busy;

  /// The button showing the tick. Cleared by [_doneTimer].
  _Step? _done;
  Timer? _doneTimer;

  /// The picker under the row is open.
  bool _open = false;
  Timer? _closeTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  /// Copies of the card in each condition, in whichever portfolio is
  /// selected: the collection's own for "Utama", the list's otherwise.
  Map<CardCondition, int>? _serverCounts(PortfolioTarget target) => ref
      .watch(
        conditionQuantitiesProvider((
          listId: target.listId,
          cardId: widget.card.id,
        )),
      )
      .valueOrNull;

  /// A chip or a pill: the row moves to that condition — its count, price
  /// and move — and an open picker folds away a beat later.
  void _pick(CardCondition condition) {
    if (_busy != null) return;
    HapticFeedback.selectionClick();
    _doneTimer?.cancel();
    setState(() {
      _condition = condition;
      _done = null;
      _awaitingRefresh = false;
    });
    if (!_open) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeAfterPick, () {
      if (mounted) setState(() => _open = false);
    });
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
    final condition = _condition;
    if (user == null || condition == null) return;
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
            condition: condition,
          )
        : await controller.setListCardQuantity(
            listId: target.listId!,
            cardId: widget.card.id,
            quantity: wanted,
            condition: condition,
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
    // write would still be loading when it asks who is signed in, and the
    // write would be dropped.
    ref.watch(authProvider);
    final target = ref.watch(selectedPortfolioProvider);
    final counts = _serverCounts(target);

    // The condition the row opens on: the one held most in this portfolio,
    // chosen once its counts are in — and again for another portfolio. A
    // guest's counts are empty, so theirs is Near Mint.
    if (_conditionFor != target && counts != null) {
      _conditionFor = target;
      _condition = defaultPickerCondition(counts);
    }
    final condition = _condition ?? CardCondition.nm;
    final server = counts == null ? null : counts[condition] ?? 0;
    final seedKey = (target: target, condition: condition);

    // Seed from the server once per target and condition, and re-seed
    // whenever it moves underneath us — an add from the scanner, or the
    // same card edited on the collection page.
    if (server != null) {
      final switched = _seededFor != seedKey;
      if (server == _saved) _awaitingRefresh = false;
      // While a write is on its way — or its refetch hasn't landed — the
      // local number is the truthful one.
      final pending = _busy != null || _awaitingRefresh;
      if (switched || (!pending && server != _saved)) {
        _seededFor = seedKey;
        _saved = server;
        _qty = server;
        _awaitingRefresh = false;
      }
    }

    final qty = _qty ?? 0;
    // What is held, with the stepper's own count standing in for the
    // server's on the condition being changed: the badges, the pills and
    // the total follow a tap before the write is back.
    final held = <CardCondition, int>{...?counts, condition: qty}
      ..removeWhere((_, n) => n <= 0);

    final prices =
        ref.watch(conditionPricesProvider(widget.card.id)).valueOrNull ??
        const <CardCondition, ConditionPrice>{};
    var total = 0;
    var unpriced = 0;
    for (final MapEntry(key: c, value: n) in held.entries) {
      final price = prices[c];
      if (price == null) {
        unpriced++;
      } else {
        total += price.price * n;
      }
    }
    final locked = _busy != null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: _TargetButton(
                    target: target,
                    onTap: () => showPortfolioPicker(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total: ${formatRupiah(total)}',
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    // A held condition nobody has sold yet adds nothing to
                    // the total; saying so keeps the figure honest.
                    if (unpriced > 0)
                      Text(
                        '$unpriced kondisi belum ada harga',
                        style: AppTypography.caption(
                          context.mutedForeground,
                        ).copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: OwnedConditionsRow.shouldShow(held)
                ? OwnedConditionsRow(owned: held, onTap: locked ? null : _pick)
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConditionTrigger(
                      condition: condition,
                      open: _open,
                      onTap: () => setState(() {
                        _closeTimer?.cancel();
                        _open = !_open;
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: _PriceColumn(price: prices[condition]),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _open
                  ? IgnorePointer(
                      // Locked while a count is being written.
                      ignoring: locked,
                      child: ConditionTogglePicker(
                        selected: condition,
                        owned: held,
                        onSelected: _pick,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

/// The stepper this panel owns, rather than the shared quantity selector.
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
        const SizedBox(width: 4),
        Container(
          width: 32,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            // The count fades rather than blinks, so a run of taps reads as
            // one number moving.
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              ready ? '$value' : '–',
              key: ValueKey(ready ? value : null),
              style: AppTypography.bodySmSemibold(
                colors.onSurface,
              ).copyWith(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 4),
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

/// One sign of the stepper — a 26pt disc — and the three states it can be
/// in.
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
    final working = widget.phase == _Phase.working;
    final done = widget.phase == _Phase.done;
    // A bound reached, or the other button holding the lock: the sign goes
    // to the design's pale grey rather than ink.
    final dimmed = widget.onTap == null && !working && !done;

    return InkWell(
      onTap: widget.onTap,
      customBorder: const CircleBorder(),
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
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: working || done ? Border.all(color: success) : null,
            ),
            child: Opacity(opacity: dimmed ? 0.35 : 1, child: child),
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
                  size: 14,
                  color: Colors.white,
                )
              : Icon(
                  widget.icon,
                  key: const ValueKey('sign'),
                  size: 12,
                  color: working ? Colors.white : colors.onSurface,
                ),
        ),
      ),
    );
  }
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
          Icon(LucideIcons.chevronDown, size: 14, color: colors.primary),
        ],
      ),
    );
  }
}

/// The picked condition's market price, with its week's move under it —
/// hidden when there is no move or nothing to measure it from.
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({this.price});

  final ConditionPrice? price;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final value = price;
    final style = AppTypography.bodySmSemibold(
      colors.onSurface,
    ).copyWith(fontSize: 13, fontWeight: FontWeight.w700);
    if (value == null) {
      return Text('Rp–', textAlign: TextAlign.right, style: style);
    }

    final then = value.price7dAgo;
    final delta = then == null || then <= 0 ? 0 : value.price - then;
    final pct = delta == 0 ? 0.0 : delta / then! * 100;
    final tone = delta > 0 ? const Color(0xFF16A34A) : colors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(formatRupiah(value.price), style: style),
        ),
        if (delta != 0)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '${delta > 0 ? '+' : '-'}${formatRupiah(delta.abs())} '
              '(${pct.abs().toStringAsFixed(1)}%)',
              style: AppTypography.badge(
                tone,
              ).copyWith(fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}
