import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/utils/auto_capture.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';

/// A card-shaped quad, optionally nudged, so drift is meaningful.
Quad _quad({double dx = 0, double dy = 0, double size = 400}) => Quad([
  Point2(dx, dy),
  Point2(dx + size, dy),
  Point2(dx + size, dy + size / 0.7159),
  Point2(dx, dy + size / 0.7159),
]);

void main() {
  final t0 = DateTime(2026, 9, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('locking', () {
    test('a card must hold still before it fires', () {
      final m = AutoCaptureMachine();

      expect(m.tick(_quad(), at(0)).action, AutoCaptureAction.tracking);
      expect(m.tick(_quad(), at(200)).action, AutoCaptureAction.tracking);
      // 400ms is the bar, and it is inclusive.
      expect(m.tick(_quad(), at(400)).action, AutoCaptureAction.capture);
    });

    test('the lock is wall-clock, not a count of frames', () {
      // Two ticks spanning 400ms fire; a phone dropping frames holds just as
      // still as one that isn't, and a streak counter would treat them
      // differently.
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      expect(m.tick(_quad(), at(410)).action, AutoCaptureAction.capture);
    });

    test('drift beyond the tolerance restarts the hold', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      // A big move at 300ms: the clock restarts, so 400ms from t0 is too soon.
      m.tick(_quad(dx: 200), at(300));
      expect(
        m.tick(_quad(dx: 200), at(400)).action,
        AutoCaptureAction.tracking,
      );
      expect(m.tick(_quad(dx: 200), at(700)).action, AutoCaptureAction.capture);
    });

    test('a small tremor does not restart the hold', () {
      // Hands shake; the tolerance exists so that a real hold still fires.
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      m.tick(_quad(dx: 2, dy: 2), at(200));
      expect(m.tick(_quad(dx: 3), at(400)).action, AutoCaptureAction.capture);
    });

    test('progress reports how far through the hold we are', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      expect(m.tick(_quad(), at(200)).progress, closeTo(0.5, 0.01));
    });

    test('losing the card mid-hold clears it', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      expect(m.tick(null, at(100)).action, AutoCaptureAction.idle);
      // The hold restarted, so the original 400ms deadline means nothing.
      expect(m.tick(_quad(), at(400)).action, AutoCaptureAction.tracking);
    });
  });

  group('re-arming', () {
    test('the same card sitting still does not fire twice', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      expect(m.tick(_quad(), at(400)).action, AutoCaptureAction.capture);

      for (final ms in [520, 640, 760, 880, 1000]) {
        expect(
          m.tick(_quad(), at(ms)).action,
          AutoCaptureAction.tracking,
          reason: 'should not re-fire at ${ms}ms',
        );
      }
    });

    test('lowering the phone re-arms after three misses', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      m.tick(_quad(), at(400));

      m.tick(null, at(520));
      m.tick(null, at(640));
      m.tick(null, at(760));

      m.tick(_quad(), at(880));
      expect(m.tick(_quad(), at(1280)).action, AutoCaptureAction.capture);
    });

    test('two misses is not enough to re-arm', () {
      // A single dropped detection mid-hold is normal and must not count as
      // the card leaving.
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      m.tick(_quad(), at(400));

      m.tick(null, at(520));
      m.tick(null, at(640));

      m.tick(_quad(), at(760));
      expect(m.tick(_quad(), at(1160)).action, AutoCaptureAction.tracking);
    });

    test('swapping cards without lowering the phone re-arms on drift', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      expect(m.tick(_quad(), at(400)).action, AutoCaptureAction.capture);

      // A different card lands in a visibly different place — no miss ticks
      // ever occur, so drift is the only signal available.
      m.tick(_quad(dx: 300, dy: 300), at(520));
      expect(
        m.tick(_quad(dx: 300, dy: 300), at(920)).action,
        AutoCaptureAction.capture,
      );
    });

    test('a nudge of the same card is not a new card', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      m.tick(_quad(), at(400));

      m.tick(_quad(dx: 20), at(520));
      expect(m.tick(_quad(dx: 20), at(920)).action, AutoCaptureAction.tracking);
    });
  });

  group('control', () {
    test('reset clears the hold and the fired quad', () {
      final m = AutoCaptureMachine();
      m.tick(_quad(), at(0));
      m.tick(_quad(), at(400));
      m.reset();

      m.tick(_quad(), at(520));
      expect(m.tick(_quad(), at(920)).action, AutoCaptureAction.capture);
    });

    test('suspending holds fire until the card moves', () {
      // What the page does while a scan is in flight: the quad is still
      // there, and firing again would queue a duplicate scan of it.
      final m = AutoCaptureMachine();
      m.suspendUntilMoved(_quad());

      m.tick(_quad(), at(0));
      expect(m.tick(_quad(), at(400)).action, AutoCaptureAction.tracking);

      m.tick(_quad(dx: 300, dy: 300), at(520));
      expect(
        m.tick(_quad(dx: 300, dy: 300), at(920)).action,
        AutoCaptureAction.capture,
      );
    });
  });
}
