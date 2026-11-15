import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../repository/app_update_repository.dart';
import '../repository/models/min_app_version.dart';

/// The update this install needs before it may run, or null.
///
/// Fails open: offline, a missing function, a bad row — the app runs. Being
/// unable to ask is not a reason to lock someone out. Refreshed when the app
/// comes back to the foreground, so raising the minimum reaches apps that
/// were left open.
final requiredUpdateProvider = FutureProvider<RequiredUpdate?>((ref) async {
  try {
    final raw = await ref
        .watch(appUpdateRepositoryProvider)
        .fetchMinVersion()
        .timeout(const Duration(seconds: 10));
    final config = MinAppVersion.parse(raw);
    if (config == null) return null;
    final installed = (await PackageInfo.fromPlatform()).version;
    return config.requiredFor(
      platform: defaultTargetPlatform,
      installed: installed,
    );
  } catch (error) {
    debugPrint('[app-update] check failed, letting the app run: $error');
    return null;
  }
});
