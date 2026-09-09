import 'package:flutter/material.dart';

/// Shown when the app cannot start at all.
///
/// Everything in [main] that runs before `runApp` — reading the build's
/// configuration, opening the Supabase client — happens while the native
/// launch screen is still on top. A throw there used to end the isolate with
/// no frame ever drawn, so the launch screen simply stayed: from the outside,
/// an app frozen on its splash. That is the least diagnosable failure the app
/// has, and it is the one most likely to reach a tester, because the usual
/// cause is a release build made without `--dart-define-from-file=env.json`
/// and nobody sees the console output of a TestFlight install.
///
/// So: draw the reason. Deliberately built from nothing but Flutter itself —
/// no Riverpod, no router, no theme, no fonts — because whatever broke may
/// well be underneath those too.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFCFAF6),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 44,
                    color: Color(0xFFB3261E),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Aplikasi gagal dijalankan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF211D1F),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Konfigurasi build ini tidak lengkap, jadi aplikasi tidak '
                    'bisa terhubung ke server. Laporkan pesan di bawah ini ke '
                    'tim Pokepedia.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF6B6462),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Selectable so a tester can copy it into a bug report
                  // instead of photographing the screen.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2EEE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontFamily: 'monospace',
                        color: Color(0xFF3A3536),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
