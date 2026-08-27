import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/simple_markdown.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Ports `app/terms/[slug]/page.tsx` — the legal documents, rendered from the
/// same markdown the site serves rather than a summary of them.
///
/// These are the terms a user is held to, so the app shows the actual text:
/// a paraphrase that drifts from the site's wording is worse than no page.
class TermsPage extends StatefulWidget {
  const TermsPage({super.key, required this.slug});

  final String slug;

  /// Ports `LEGAL_DOCS` from `features/information/legal/docs.ts`.
  static const titles = {
    'syarat-dan-ketentuan': 'Syarat & Ketentuan',
    'kebijakan-privasi': 'Kebijakan Privasi',
    'kondisi-kartu': 'Panduan Kondisi Kartu',
  };

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  late Future<String> _content = _load();

  Future<String> _load() =>
      rootBundle.loadString('assets/legal/${widget.slug}.md');

  @override
  void didUpdateWidget(covariant TermsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) _content = _load();
  }

  @override
  Widget build(BuildContext context) {
    final known = TermsPage.titles.containsKey(widget.slug);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: !known
            ? const EmptyState(
                icon: Icons.description_outlined,
                title: 'Dokumen tidak ditemukan',
              )
            : FutureBuilder<String>(
                future: _content,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const EmptyState(
                      icon: Icons.description_outlined,
                      title: 'Gagal memuat dokumen',
                    );
                  }
                  final markdown = snapshot.data;
                  if (markdown == null) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      // The documents open with their own H1, which the
                      // renderer draws — no second title here.
                      SimpleMarkdown(data: markdown),
                      const SizedBox(height: 24),
                      Text(
                        'Versi lengkap juga tersedia di pokepedia.id.',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
