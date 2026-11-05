import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/setup_kit.dart';

/// A Buka Toko step: what it asks, scrolling, over a footer that stays put
/// — and rises with the keyboard, so the button is never under it.
class SetupStepLayout extends StatelessWidget {
  const SetupStepLayout({
    super.key,
    required this.palette,
    required this.content,
    required this.footer,
    this.top = 16,
    this.physics,
  });

  final DesignPalette palette;
  final List<Widget> content;
  final List<Widget> footer;

  /// Space above the progress bar; the designs vary it by step.
  final double top;

  /// Set to stop the page scrolling while a finger is on a map in it, so
  /// the drag pans the map instead.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: physics,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...content, const SizedBox(height: 24)],
              ),
            ),
          ),
          ...footer,
        ],
      ),
    );
  }
}

/// The state of one checklist row.
enum SetupRowState {
  /// Still to do; the icon says what it is.
  todo,

  /// Done: a green tick, and "Selesai".
  done,

  /// Can wait: the icon on a quiet tile, and "Opsional".
  optional,
}

/// One row of the Buka Toko checklist — the launcher's "Yang perlu
/// disiapkan" and the finished store's summary.
class SetupChecklistRow extends StatelessWidget {
  const SetupChecklistRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.state,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// The note on the right: "±1 mnt", "Opsional", "Selesai".
  final String meta;
  final SetupRowState state;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    final (tile, iconColor, metaColor) = switch (state) {
      SetupRowState.done => (
        palette.successSoft,
        palette.successText,
        palette.successText,
      ),
      SetupRowState.optional => (palette.chip, palette.muted, palette.muted),
      SetupRowState.todo => (palette.brandSoft, palette.brand, palette.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tile, shape: BoxShape.circle),
            child: Icon(
              state == SetupRowState.done ? LucideIcons.check : icon,
              size: 18,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: setupText(15, palette.ink, FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: setupText(13, palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(meta, style: setupText(12, metaColor, FontWeight.w500)),
        ],
      ),
    );
  }
}

/// White card with rows divided by hairlines, optionally under a header.
class SetupCard extends StatelessWidget {
  const SetupCard({
    super.key,
    required this.palette,
    required this.rows,
    this.header,
  });

  final DesignPalette palette;
  final List<Widget> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final divider = Container(height: 1, color: palette.border);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
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
