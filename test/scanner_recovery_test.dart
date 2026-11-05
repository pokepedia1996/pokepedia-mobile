import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/presentation/widgets/scan_status_pill.dart';
import 'package:pokepedia_mobile/features/scanner/utils/scan_retry.dart';

void main() {
  ScanPillStatus status({
    bool processing = false,
    bool capturing = false,
    bool present = false,
    bool tracking = false,
    bool cooldown = false,
  }) => scannerPillStatus(
    processing: processing,
    capturing: capturing,
    paused: false,
    coolingDown: cooldown,
    capturedCardPresent: present,
    tracking: tracking,
  );
  test(
    'network processing is visible while capture is still single-flight',
    () {
      expect(
        status(processing: true, capturing: true, present: true),
        ScanPillStatus.processing,
      );
    },
  );
  test('previous result does not hide a new card or an empty frame', () {
    expect(status(present: true), ScanPillStatus.done);
    expect(status(), ScanPillStatus.searching);
    expect(status(tracking: true), ScanPillStatus.locking);
  });
  test('server wait takes priority over tracking', () {
    expect(status(cooldown: true, tracking: true), ScanPillStatus.coolingDown);
    for (final jitter in [0.0, 0.5, 1.0]) {
      expect(
        scanRetryDelay(retryAfter: const Duration(seconds: 60), jitter: jitter),
        greaterThanOrEqualTo(const Duration(seconds: 60)),
      );
    }
    expect(
      scanRetryDelay(retryAfter: const Duration(milliseconds: 100), jitter: 0),
      const Duration(milliseconds: 900),
    );
    expect(scanRetryDelay(jitter: 1), const Duration(milliseconds: 1260));
  });
}
