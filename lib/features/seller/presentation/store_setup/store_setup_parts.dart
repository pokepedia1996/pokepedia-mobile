import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/setup_kit.dart';

/// A Buka Toko step's content: what it asks, scrolling, over a footer that
/// stays put — and rises with the keyboard, so the button is never under it.
///
/// The page around it — the paper and the step header — belongs to
/// StoreSetupPage and stays as the steps change; the blocks of [content]
/// arrive one after another as this step comes in.
class SetupStepLayout extends StatelessWidget {
  const SetupStepLayout({
    super.key,
    required this.content,
    required this.footer,
    this.physics,
  });

  final List<Widget> content;
  final List<Widget> footer;

  /// Set to stop the page scrolling while a finger is on a map in it, so
  /// the drag pans the map instead.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: physics,
              // Room for a sticker card's hard shadow at the edges.
              clipBehavior: Clip.none,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < content.length; i++)
                    CoretanReveal.at(i, child: content[i]),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          for (var i = 0; i < footer.length; i++)
            CoretanReveal.at(content.length + i, child: footer[i]),
        ],
      ),
    );
  }
}

/// The eyebrow, the two-line headline and the line under it that open
/// every step.
class SetupIntro extends StatelessWidget {
  const SetupIntro({
    super.key,
    required this.eyebrow,
    required this.first,
    required this.second,
    this.sub,
    this.subWidget,
  });

  final String eyebrow;
  final String first;
  final String second;
  final String? sub;

  /// In place of [sub], for a line with a link in it.
  final Widget? subWidget;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoretanEyebrow(eyebrow),
          const SizedBox(height: 8),
          SetupHeadline(
            first: first,
            second: second,
            palette: palette,
            size: 40,
            lineHeight: 42,
          ),
          if (sub != null || subWidget != null) ...[
            const SizedBox(height: 10),
            subWidget ??
                Text(
                  sub!,
                  style: setupText(18, palette.muted, FontWeight.w400, 1.4),
                ),
          ],
        ],
      ),
    );
  }
}

/// One row of a Buka Toko checklist — the launcher's "Yang perlu
/// disiapkan" and the finished store's summary: a drawn icon, what it is,
/// and a handwritten note on the right.
class SetupChecklistRow extends StatelessWidget {
  const SetupChecklistRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.meta,
  });

  final Widget icon;
  final String title;
  final String subtitle;

  /// The note on the right: "±1 mnt", "opsional", "selesai".
  final Widget? meta;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox.square(dimension: 46, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: setupText(17, palette.ink, FontWeight.w800)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: setupText(14.5, palette.muted),
                  ),
                ],
              ],
            ),
          ),
          if (meta != null) ...[const SizedBox(width: 10), meta!],
        ],
      ),
    );
  }
}

/// White card with rows divided by hairlines, optionally under a header.
class SetupCard extends StatelessWidget {
  const SetupCard({super.key, required this.rows, this.header});

  final List<Widget> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, thickness: 1, color: AppColors.onbLine);
    return CoretanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header!, divider],
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) divider,
            rows[i],
          ],
        ],
      ),
    );
  }
}
