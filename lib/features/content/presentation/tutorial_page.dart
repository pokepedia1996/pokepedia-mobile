import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/simple_markdown.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/tutorial_docs.dart';

/// Ports `app/tutorial/page.tsx` — the twelve guides as an accordion, each
/// opening onto its markdown body and that guide's own FAQ accordion.
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Tutorial', style: AppTypography.h1(colors.onSurface)),
            const SizedBox(height: 4),
            Text(
              'Panduan lengkap untuk memulai dan menggunakan pokepedia.id.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            for (final doc in tutorialDocs)
              _TutorialTile(key: ValueKey(doc.slug), doc: doc),
          ],
        ),
      ),
    );
  }
}

/// One collapsed guide. The markdown is only read once it's opened — twelve
/// bundled files is not much, but there's no reason to parse the eleven a
/// reader isn't looking at.
class _TutorialTile extends StatefulWidget {
  const _TutorialTile({super.key, required this.doc});

  final TutorialDoc doc;

  @override
  State<_TutorialTile> createState() => _TutorialTileState();
}

class _TutorialTileState extends State<_TutorialTile> {
  Future<SplitTutorial>? _content;

  Future<SplitTutorial> _load() async {
    final raw = await rootBundle.loadString(widget.doc.asset);
    return splitTutorial(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // A Material rather than a coloured Container: the tile paints its ink
      // on the nearest Material, and a decoration in between would hide the
      // ripple (Flutter asserts on exactly that).
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.borderColor),
          ),
          child: Theme(
            // The stock divider is a line across the whole tile; the card's own
            // border already does that job.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              onExpansionChanged: (open) {
                if (!open || _content != null) return;
                // Kick the load off first, then assign inside setState: an
                // arrow body would hand setState the Future it returns,
                // which Flutter rejects.
                final loading = _load();
                setState(() {
                  _content = loading;
                });
              },
              title: Text(
                widget.doc.title,
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.doc.description,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              children: [
                FutureBuilder<SplitTutorial>(
                  future: _content,
                  builder: (context, snapshot) {
                    final content = snapshot.data;
                    if (content == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SimpleMarkdown(data: content.body),
                        if (content.faq.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'FAQ',
                            style: AppTypography.bodySemibold(colors.onSurface),
                          ),
                          const SizedBox(height: 6),
                          for (final item in content.faq) _FaqTile(item: item),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A question inside a guide — web nests a second accordion here, so this
/// one collapses too.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item});

  final TutorialFaqItem item;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          item.question,
          style: AppTypography.bodySm(context.appColors.onSurface),
        ),
        children: [SimpleMarkdown(data: item.answer)],
      ),
    );
  }
}
