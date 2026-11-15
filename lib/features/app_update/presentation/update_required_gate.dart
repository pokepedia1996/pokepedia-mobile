import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/design_palette.dart';
import '../../../shared/widgets/coretan_kit.dart';
import '../repository/models/min_app_version.dart';
import '../usecase/required_update_provider.dart';

/// Covers the whole app with [UpdateRequiredPage] when this version is too
/// old to run. Above onboarding and every route: there is nothing an old
/// version should be let into.
///
/// Nothing shows while the check is in flight, so a launch never flashes the
/// screen; the app is usable for that moment, as it is when the check fails.
class UpdateRequiredGate extends ConsumerWidget {
  const UpdateRequiredGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(requiredUpdateProvider).valueOrNull;
    return Stack(
      children: [
        child,
        if (update != null)
          Positioned.fill(child: UpdateRequiredPage(update: update)),
      ],
    );
  }
}

/// "Update to continue", with the way to the store. No way past it.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, required this.update});

  final RequiredUpdate update;

  Future<void> _openStore() async {
    final uri = Uri.tryParse(update.storeUrl);
    if (uri == null) return;
    await launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              children: [
                const Spacer(),
                Icon(LucideIcons.download, size: 48, color: palette.brand),
                const SizedBox(height: 20),
                Text(
                  'Update aplikasi untuk melanjutkan',
                  textAlign: TextAlign.center,
                  style: AppTypography.h2(palette.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Versi ini sudah tidak didukung. Update ke versi '
                  '${update.minimum} atau yang lebih baru untuk terus '
                  'memakai pokepedia.id.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(palette.muted),
                ),
                const Spacer(),
                CoretanButton(label: 'Update sekarang', onPressed: _openStore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
