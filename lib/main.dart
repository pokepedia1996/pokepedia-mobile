import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/startup_error_app.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  // Bound before the try so the error screen has a binding to run on even if
  // Supabase never gets far enough to create one itself.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  } catch (error, stack) {
    // Reading AppConfig is itself a throwing operation in release: a build
    // made without --dart-define-from-file has no SUPABASE_URL, and
    // AppConfig deliberately fails loudly rather than pointing a shipped app
    // at localhost. Loudly, though, only reached the console — and this
    // throws before the first frame, so the native splash stayed up and the
    // app looked hung. Show the reason on screen instead. See
    // [StartupErrorApp].
    debugPrint('[startup] failed: $error\n$stack');
    runApp(StartupErrorApp(message: '$error'));
    return;
  }

  runApp(const ProviderScope(child: PokepediaApp()));
}
