import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/app_update/presentation/update_required_gate.dart';
import 'package:pokepedia_mobile/features/app_update/repository/models/min_app_version.dart';
import 'package:pokepedia_mobile/features/app_update/usecase/required_update_provider.dart';

void main() {
  group('isVersionOlder', () {
    test('compares major, minor and patch as numbers', () {
      expect(isVersionOlder('1.2.9', '1.3.0'), isTrue);
      expect(isVersionOlder('1.10.0', '1.9.0'), isFalse);
      expect(isVersionOlder('1.3.0', '1.3.0'), isFalse);
      expect(isVersionOlder('2.0.0', '1.3.0'), isFalse);
    });

    test('ignores the build number and pads a short version', () {
      expect(isVersionOlder('1.3.0+12', '1.3.0'), isFalse);
      expect(isVersionOlder('1.2', '1.2.1'), isTrue);
    });

    test('lets the app run on a version it cannot read', () {
      expect(isVersionOlder('1.2.0', 'latest'), isFalse);
      expect(isVersionOlder('dev', '1.3.0'), isFalse);
    });
  });

  group('MinAppVersion', () {
    test('reads each platform and its store page', () {
      final config = MinAppVersion.parse(
        '{"ios":"1.3.0","android":"1.4.0",'
        '"iosStoreUrl":"https://apps.apple.com/app/id1"}',
      )!;
      expect(
        config.requiredFor(platform: TargetPlatform.iOS, installed: '1.2.0'),
        const RequiredUpdate(
          minimum: '1.3.0',
          storeUrl: 'https://apps.apple.com/app/id1',
        ),
      );
      expect(
        config.requiredFor(
          platform: TargetPlatform.android,
          installed: '1.3.5',
        ),
        const RequiredUpdate(
          minimum: '1.4.0',
          storeUrl:
              'https://play.google.com/store/apps/details?id=id.pokepedia.app',
        ),
      );
    });

    test('asks nothing of a current version or an unlisted platform', () {
      final config = MinAppVersion.parse('{"android":"1.3.0"}')!;
      expect(
        config.requiredFor(
          platform: TargetPlatform.android,
          installed: '1.3.0',
        ),
        isNull,
      );
      expect(
        config.requiredFor(platform: TargetPlatform.iOS, installed: '1.0.0'),
        isNull,
      );
    });

    test('a missing or bad row is no minimum', () {
      expect(MinAppVersion.parse(null), isNull);
      expect(MinAppVersion.parse(''), isNull);
      expect(MinAppVersion.parse('1.3.0'), isNull);
      expect(MinAppVersion.parse('["1.3.0"]'), isNull);
    });
  });

  group('UpdateRequiredGate', () {
    Widget app(RequiredUpdate? update) => ProviderScope(
      overrides: [requiredUpdateProvider.overrideWith((ref) async => update)],
      child: MaterialApp(
        builder: (context, child) => UpdateRequiredGate(child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );

    testWidgets('covers the app when an update is required', (tester) async {
      await tester.pumpWidget(
        app(const RequiredUpdate(minimum: '1.3.0', storeUrl: 'https://x')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update aplikasi untuk melanjutkan'), findsOneWidget);
      expect(find.textContaining('1.3.0'), findsOneWidget);
    });

    testWidgets('stays out of the way otherwise', (tester) async {
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('Update aplikasi untuk melanjutkan'), findsNothing);
    });
  });
}
