/// The lock-and-fire logic behind auto-capture. Ports the state machine in
/// `features/scanner/hooks/useAutoCapture.ts`.
///
/// Pure and clock-injected on purpose: every rule here is a *timing* rule, and
/// timing is the one thing that cannot be checked by looking at it. The caller
/// owns the camera, the model and the 120ms tick; this owns only the question
/// "given what the detector just said, should we fire?".
library;

import 'warp_quad.dart';

/// How long a quad must hold still before capture fires.
///
/// Wall-clock rather than a frame streak, deliberately. A streak counts ticks,
/// so it means different things on a phone dropping frames under load than on
/// one that isn't — the user's hand held just as still either way, and only
/// one of them would have fired.
const lockDuration = Duration(milliseconds: 400);

/// Maximum mean corner movement, as a fraction of the quad's own diagonal,
/// that still counts as holding still.
const maxLockDrift = 0.06;

/// Consecutive ticks with no usable quad before the machine will fire again.
///
/// Lowering the phone between cards produces exactly this: the card leaves,
/// a few ticks miss, and the next card is a new capture rather than a repeat
/// of the last one.
const rearmMissTicks = 3;

/// How far a new quad must sit from the one that last fired to count as a
/// different card. Covers swapping cards without lowering the phone, where no
/// miss ticks ever occur.
const rearmDriftFraction = 0.25;

/// What the caller should do after a tick.
enum AutoCaptureAction {
  /// Nothing to show — no card in view.
  idle,

  /// A card is visible but hasn't held still long enough yet.
  tracking,

  /// Fire the capture now.
  capture,
}

/// One tick's outcome, including the quad to draw and the reason.
class AutoCaptureTick {
  const AutoCaptureTick({required this.action, this.quad, this.progress = 0});

  final AutoCaptureAction action;

  /// The quad to outline on the preview, if any.
  final Quad? quad;

  /// How far through [lockDuration] the current hold is, 0–1 — the fill on
  /// the lock indicator.
  final double progress;
}

/// Decides when a stable quad becomes a capture.
class AutoCaptureMachine {
  AutoCaptureMachine({this.lockFor = lockDuration});

  final Duration lockFor;

  /// The quad the current hold started from, and when it started.
  Quad? _holding;
  DateTime? _holdingSince;

  /// Consecutive ticks with no usable quad.
  int _misses = 0;

  /// The quad that last fired. Non-null means the machine is disarmed and
  /// waiting for a reason to believe a *new* card is in view.
  Quad? _lastFired;

  /// Feeds one detector result in and gets back what to do.
  ///
  /// [quad] is null when the detector found nothing that passed its gates.
  AutoCaptureTick tick(Quad? quad, DateTime now) {
    if (quad == null) {
      _misses++;
      _holding = null;
      _holdingSince = null;
      // Enough consecutive misses means the card genuinely left the frame, so
      // whatever fired last is no longer what we are looking at.
      if (_misses >= rearmMissTicks) _lastFired = null;
      return const AutoCaptureTick(action: AutoCaptureAction.idle);
    }

    _misses = 0;

    // Still looking at the card we just captured — track it, but don't fire
    // again until it moves far enough to be a different card.
    final lastFired = _lastFired;
    if (lastFired != null) {
      if (quad.driftFrom(lastFired) <= rearmDriftFraction) {
        return AutoCaptureTick(
          action: AutoCaptureAction.tracking,
          quad: quad,
          progress: 1,
        );
      }
      _lastFired = null;
    }

    final holding = _holding;
    final since = _holdingSince;

    // A new hold, or the old one moved too far to still be the same pose.
    if (holding == null ||
        since == null ||
        quad.driftFrom(holding) > maxLockDrift) {
      _holding = quad;
      _holdingSince = now;
      return AutoCaptureTick(action: AutoCaptureAction.tracking, quad: quad);
    }

    final held = now.difference(since);
    if (held >= lockFor) {
      _lastFired = quad;
      _holding = null;
      _holdingSince = null;
      return AutoCaptureTick(
        action: AutoCaptureAction.capture,
        quad: quad,
        progress: 1,
      );
    }

    return AutoCaptureTick(
      action: AutoCaptureAction.tracking,
      quad: quad,
      progress: (held.inMilliseconds / lockFor.inMilliseconds).clamp(0.0, 1.0),
    );
  }

  /// Drops all state — used when the scanner is paused, the language changes,
  /// or a capture fails and the user should get a clean run at it.
  void reset() {
    _holding = null;
    _holdingSince = null;
    _misses = 0;
    _lastFired = null;
  }

  /// Disarms without clearing the tracked pose, so the machine won't fire
  /// again while a scan is in flight.
  void suspendUntilMoved(Quad firedOn) {
    _lastFired = firedOn;
    _holding = null;
    _holdingSince = null;
  }
}
