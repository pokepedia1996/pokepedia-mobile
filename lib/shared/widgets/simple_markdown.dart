import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Renders the markdown the tutorial and terms content is written in.
///
/// Deliberately not a full CommonMark implementation, and not a package: the
/// bundled documents use headings, ordered and bulleted lists, blockquotes,
/// one small table, and inline bold / links / code. Supporting exactly that
/// keeps the typography on [AppTypography] rather than a package's own
/// theme, which is what makes it look like the rest of the app.
class SimpleMarkdown extends StatefulWidget {
  const SimpleMarkdown({super.key, required this.data});

  final String data;

  /// The anchor a heading answers to, by GitHub's rules — which is what these
  /// documents were written against: lowercase, drop anything that is not a
  /// letter, digit, space or hyphen, then spaces to hyphens.
  ///
  /// Runs of hyphens are deliberately left alone. "Integrity & Imperfection"
  /// anchors as `integrity--imperfection` there, and collapsing them here
  /// would stop that link resolving.
  ///
  /// Public because it is the contract between a document's table of contents
  /// and this renderer: a test pins every bundled document's links against it.
  static String headingSlug(String heading) => heading
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 \-]'), '')
      .replaceAll(' ', '-');

  @override
  State<SimpleMarkdown> createState() => _SimpleMarkdownState();
}

class _SimpleMarkdownState extends State<SimpleMarkdown> {
  /// One key per heading slug, so a `[Label](#slug)` link in a document's own
  /// table of contents can find the heading it names. Filled while rendering
  /// and dropped when the document changes, since the next one's headings are
  /// not these.
  final _anchors = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant SimpleMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _anchors.clear();
  }

  GlobalKey _anchorFor(String heading) =>
      _anchors.putIfAbsent(SimpleMarkdown.headingSlug(heading), GlobalKey.new);

  /// Scrolls the heading a table-of-contents entry names into view.
  ///
  /// Silent when the slug matches no heading: the documents are edited by
  /// hand, so a renamed heading leaves a link pointing at nothing, and
  /// jumping somewhere arbitrary would be worse than staying put.
  Future<void> _scrollToAnchor(String slug) async {
    final target = _anchors[slug]?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      // Leading edge of the viewport, which `AppBarOverlayBody`'s SafeArea has
      // already cleared of the app bar, so the heading lands in view rather
      // than under it.
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _blocks(context, widget.data),
    );
  }

  List<Widget> _blocks(BuildContext context, String source) {
    final colors = context.appColors;
    final blocks = <Widget>[];
    final lines = source.split('\n');
    final tableRows = <List<String>>[];

    void flushTable() {
      if (tableRows.isEmpty) return;
      blocks.add(_Table(rows: List.of(tableRows)));
      tableRows.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('|')) {
        // `|---|---|` is the header rule, not a row.
        if (!RegExp(r'^\|[\s\-:|]+\|$').hasMatch(trimmed)) {
          tableRows.add(
            trimmed
                .split('|')
                .sublist(1, trimmed.split('|').length - 1)
                .map((cell) => cell.trim())
                .toList(),
          );
        }
        continue;
      }
      flushTable();

      if (trimmed.isEmpty) continue;

      if (trimmed == '---' || trimmed == '***') {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.borderColor),
          ),
        );
      } else if (trimmed.startsWith('# ')) {
        blocks.add(
          Padding(
            key: _anchorFor(trimmed.substring(2)),
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 18, bottom: 8),
            child: Text(
              trimmed.substring(2),
              style: AppTypography.h2(colors.onSurface),
            ),
          ),
        );
      } else if (trimmed.startsWith('#### ') || trimmed.startsWith('### ')) {
        blocks.add(
          Padding(
            key: _anchorFor(trimmed.replaceFirst(RegExp(r'^#{3,4} '), '')),
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 14, bottom: 4),
            child: Text(
              trimmed.replaceFirst(RegExp(r'^#{3,4} '), ''),
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
          ),
        );
      } else if (trimmed.startsWith('## ')) {
        blocks.add(
          Padding(
            key: _anchorFor(trimmed.substring(3)),
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 16, bottom: 6),
            child: Text(
              trimmed.substring(3),
              style: AppTypography.h3(colors.onSurface),
            ),
          ),
        );
      } else if (trimmed.startsWith('> ')) {
        blocks.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border(left: BorderSide(color: colors.primary, width: 3)),
            ),
            child: _inline(context, trimmed.substring(2)),
          ),
        );
      } else if (RegExp(r'^\d+\. ').hasMatch(trimmed)) {
        blocks.add(
          _ListItem(
            marker: '${trimmed.split('. ').first}.',
            child: _inline(
              context,
              trimmed.replaceFirst(RegExp(r'^\d+\. '), ''),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ')) {
        blocks.add(
          _ListItem(
            marker: '•',
            // Nested bullets are indented in the source; keep that shape.
            indent: line.startsWith('   ') || line.startsWith('\t') ? 16 : 0,
            child: _inline(context, trimmed.substring(2)),
          ),
        );
      } else {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _inline(context, trimmed),
          ),
        );
      }
    }
    flushTable();

    return blocks;
  }

  Widget _inline(BuildContext context, String text) =>
      _InlineText(text: text, onAnchor: _scrollToAnchor);
}

/// Bold, inline code and links inside one paragraph.
class _InlineText extends StatelessWidget {
  const _InlineText({required this.text, this.onAnchor});

  final String text;

  /// Handles `#heading` hrefs. Null where nothing is scrollable around the
  /// text, in which case such a link simply does nothing.
  final Future<void> Function(String slug)? onAnchor;

  static final _pattern = RegExp(
    r'\*\*(.+?)\*\*|`(.+?)`|\[([^\]]+)\]\(([^)]+)\)',
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = AppTypography.bodySm(colors.onSurface);
    final spans = <InlineSpan>[];
    var index = 0;

    for (final match in _pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: ' ${match.group(2)} ',
            style: TextStyle(
              backgroundColor: colors.secondary,
              fontFamily: 'monospace',
            ),
          ),
        );
      } else {
        final label = match.group(3)!;
        final href = match.group(4)!;
        spans.add(
          TextSpan(
            text: label,
            style: TextStyle(
              color: colors.primary,
              decoration: TextDecoration.underline,
              decorationColor: colors.primary,
            ),
            recognizer: TapGestureRecognizer()..onTap = () => _tap(href),
          ),
        );
      }
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }

    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// A `#heading` href is the document pointing at itself — the tables of
  /// contents these documents open with — so it scrolls rather than leaving
  /// the app. Everything else is a real destination.
  void _tap(String href) {
    if (href.startsWith('#')) {
      onAnchor?.call(href.substring(1));
      return;
    }
    _open(href);
  }

  /// Site-relative hrefs in the docs point at pokepedia.id pages that the app
  /// has its own screens for; opening them externally is the honest fallback
  /// rather than guessing at a route.
  Future<void> _open(String href) async {
    final uri = Uri.parse(
      href.startsWith('/') ? 'https://pokepedia.id$href' : href,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({required this.marker, required this.child, this.indent = 0});

  final String marker;
  final Widget child;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 3, 0, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A markdown table, stacked rather than gridded.
///
/// These documents carry three-column tables with sentence-long cells; laid
/// out as columns on a phone each one is about a dozen characters wide. Each
/// data row becomes a block instead, labelled by the header it came under —
/// the usual responsive-table treatment.
class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final header = rows.first;
    final body = rows.length > 1 ? rows.sublist(1) : rows;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in body)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appColors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.isNotEmpty && row.first.isNotEmpty)
                    _InlineText(text: row.first),
                  for (var c = 1; c < row.length; c++)
                    if (row[c].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c < header.length && header[c].isNotEmpty)
                              SizedBox(
                                width: 96,
                                child: Text(
                                  header[c],
                                  style: AppTypography.caption(
                                    context.mutedForeground,
                                  ),
                                ),
                              ),
                            Expanded(child: _InlineText(text: row[c])),
                          ],
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
