import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/utils/scanner_camera_session.dart';

void main() {
  test(
    'resume opens a fresh camera after suspension cleared the handle',
    () async {
      var next = 0;
      final closed = <int>[];
      final session = ScannerCameraSession<int>(
        open: () async => ++next,
        close: (id) async {
          closed.add(id);
        },
      );
      await session.start();
      final token = session.generation;
      expect(session.current, 1);
      await session.stop();
      expect(session.current, isNull);
      expect(session.isCurrent(token), isFalse);
      await session.start();
      expect(session.current, 2);
      expect(closed, [1]);
      await session.stop();
    },
  );

  test(
    'a suspended startup is disposed before resume opens another camera',
    () async {
      final opening = Completer<int>();
      final closing = Completer<void>();
      final events = <String>[];
      var calls = 0;
      final session = ScannerCameraSession<int>(
        open: () {
          events.add('open');
          return ++calls == 1 ? opening.future : Future.value(2);
        },
        close: (id) async {
          events.add('close $id');
          if (id == 1) await closing.future;
        },
      );
      final first = session.start();
      await Future<void>.delayed(Duration.zero);
      final stop = session.stop();
      final resumed = session.start();
      opening.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(session.current, isNull);
      expect(events, ['open', 'close 1']);
      closing.complete();
      await Future.wait([first, stop, resumed]);
      expect(session.current, 2);
      expect(events, ['open', 'close 1', 'open']);
      await session.stop();
    },
  );

  test('failed startup does not poison retry', () async {
    var calls = 0;
    final session = ScannerCameraSession<int>(
      open: () async {
        if (++calls == 1) throw StateError('camera unavailable');
        return calls;
      },
      close: (_) async {},
    );
    await expectLater(session.start(), throwsStateError);
    await session.start();
    expect(session.current, 2);
    await session.stop();
  });
}
