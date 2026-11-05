import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/scanner/presentation/widgets/scan_candidate_sheet.dart';
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';
import 'package:pokepedia_mobile/features/scanner/repository/scanner_repository.dart';
import 'package:pokepedia_mobile/features/scanner/usecase/scanner_notifier.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_capture.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';
import 'package:pokepedia_mobile/features/scanner/utils/detector_worker.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

class _Candidates implements ScannerRepository {
  @override
  Future<ScanResponse> scan({
    required Uint8List imageBytes,
    required CardLanguage language,
    Map<String, dynamic>? captureMeta,
  }) async => ScanResponse.fromJson({
    'confident': false,
    'matches': [
      {
        'card': {'id': 1, 'name_id': 'Victini'},
        'distance': 0.28,
      },
      {
        'card': {'id': 2, 'name_id': 'Jirachi'},
        'distance': 0.29,
      },
    ],
    'variants': <dynamic>[],
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('sharp background cannot win against a focused card', () {
    final backdrop = img.Image(width: 128, height: 128);
    final card = img.Image(width: 128, height: 128);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        final inside = x >= 32 && x < 96 && y >= 16 && y < 112;
        final detail = ((x ~/ 4 + y ~/ 4).isEven ? 240 : 10);
        final a = inside ? 128 : detail;
        final b = inside ? detail : 128;
        backdrop.setPixelRgb(x, y, a, a, a);
        card.setPixelRgb(x, y, b, b, b);
      }
    }
    const region = Quad([
      Point2(.25, .125),
      Point2(.75, .125),
      Point2(.75, .875),
      Point2(.25, .875),
    ]);
    expect(scoreCardFocus(backdrop, region), closeTo(0, .01));
    expect(scoreCardFocus(card, region), greaterThan(100));
  });

  test('capture retains 720p detail while tracking stays at 768px', () async {
    final worker = await DetectorWorker.spawn();
    addTearDown(worker.dispose);
    final bytes = Uint8List(720 * 1280 * 4);
    final planes = [(bytes: bytes, bytesPerRow: 720 * 4, bytesPerPixel: 4)];
    final tracking = await worker.prepareFrameForTest(
      planes: planes,
      width: 720,
      height: 1280,
      sensorOrientation: 0,
    );
    expect(tracking!.height, 768);
    await worker.beginBurst();
    await worker.offerBurstFrameForTest(
      planes: planes,
      width: 720,
      height: 1280,
      sensorOrientation: 0,
    );
    final capture = await worker.burstTensor();
    expect(capture!.width, 720);
    expect(capture.height, 1280);
  });

  test('refinement cannot shrink a card into its artwork', () {
    const card = Quad([
      Point2(0, 0),
      Point2(200, 0),
      Point2(200, 280),
      Point2(0, 280),
    ]);
    const artwork = Quad([
      Point2(30, 42),
      Point2(170, 42),
      Point2(170, 238),
      Point2(30, 238),
    ]);
    expect(refinementAgrees(card, artwork), isFalse);
    expect(refinementAgrees(card, card.offsetBy(3, 2)), isTrue);
    expect(refinementAgrees(card, card.offsetBy(100, 0)), isFalse);
  });

  test(
    'uncertain foil candidates survive the old uncalibrated blur veto',
    () async {
      final container = ProviderContainer(
        overrides: [scannerRepositoryProvider.overrideWithValue(_Candidates())],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(scannerProvider.notifier)
          .scan(
            capture: CardCapture(
              bytes: Uint8List(0),
              sharpness: 866,
              luma: 126,
              width: 240,
              height: 340,
            ),
            language: CardLanguage.id,
          );
      expect(result, isA<ScanMatched>());
      final candidates = result as ScanMatched;
      expect(candidates.confident, isFalse);
      expect(candidates.matches.length, 2);
    },
  );

  testWidgets('candidate picker never selects until the user chooses', (
    tester,
  ) async {
    ScanCard? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ScanCandidateSheet(
            candidates: const [
              ScanCard(id: 1, nameId: 'Victini'),
              ScanCard(id: 2, nameId: 'Jirachi'),
            ],
            onSelect: (card) => selected = card,
            onSearch: () {},
          ),
        ),
      ),
    );
    expect(selected, isNull);
    await tester.tap(find.text('Victini'));
    expect(selected?.id, 1);
  });
}
