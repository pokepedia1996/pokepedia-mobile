import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/usecase/notification_push_notifier.dart';
import 'router/app_router.dart';

class PokepediaApp extends ConsumerWidget {
  const PokepediaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Kept alive for the life of the app: it follows the session on its own,
    // subscribing to this user's notifications and showing them.
    ref.watch(notificationPushProvider);

    return MaterialApp.router(
      title: 'pokepedia.id',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
