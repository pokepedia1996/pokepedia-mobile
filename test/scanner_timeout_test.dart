import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/repository/scanner_repository.dart';
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';
import 'package:pokepedia_mobile/features/scanner/usecase/scanner_notifier.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_capture.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

class _HangingRepository implements ScannerRepository {
  final response = Completer<ScanResponse>();
  @override
  Future<ScanResponse> scan({
    required Uint8List imageBytes,
    required CardLanguage language,
    Map<String, dynamic>? captureMeta,
  }) => response.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'a hung scan releases loading and a late response cannot overwrite failure',
    (tester) async {
      final repository = _HangingRepository();
      final container = ProviderContainer(
        overrides: [scannerRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final pending = container
          .read(scannerProvider.notifier)
          .scan(
            capture: CardCapture(
              bytes: Uint8List(0),
              sharpness: 100,
              luma: 100,
              width: 1,
              height: 1,
            ),
            language: CardLanguage.id,
          );
      expect(container.read(scannerProvider), isA<ScanLoading>());
      await tester.pump(const Duration(seconds: 64));
      expect(container.read(scannerProvider), isA<ScanLoading>());
      await tester.pump(const Duration(seconds: 1));
      expect(await pending, isA<ScanFailed>());
      final failure = container.read(scannerProvider);
      repository.response.complete(
        ScanResponse.fromJson({
          'matches': [],
          'variants': [],
          'confident': false,
        }),
      );
      await tester.pump();
      expect(identical(container.read(scannerProvider), failure), isTrue);
    },
  );
}
