import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/widgets/empty_state.dart';
import 'router/routes.dart';

/// Where the router lands a location it has no page for: an old or mistyped
/// link, or one the app never had. go_router's own screen printed the raw
/// exception ("GoException: no routes for location: …"); this says it in
/// words and offers the way back.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: LucideIcons.searchX,
          title: 'Halaman tidak ditemukan',
          description: 'Tautan ini mungkin salah atau sudah tidak berlaku.',
          action: ElevatedButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Kembali ke Beranda'),
          ),
        ),
      ),
    );
  }
}
