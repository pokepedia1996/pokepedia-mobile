import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// The app's one search input.
///
/// Every search box used to be a bare [TextField] leaning on the global
/// `inputDecorationTheme` — the same decoration the address and bank *forms*
/// use — while Beranda's built its own pill by hand. So the field people meet
/// first looked nothing like the fifteen behind it, and those fifteen looked
/// like data entry rather than search. This is Beranda's pill, extracted, so
/// there is one answer instead of sixteen.
///
/// Searching is not form filling, which is why it keeps its own shape: a full
/// radius, the muted fill, and the magnifier inline rather than as a
/// `prefixIcon` whose padding the theme controls.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.trailing,
    this.onScan,
  });

  final String hintText;

  /// Optional — one is made internally when the caller has no use for it.
  /// Supplied or not, the clear button needs to watch it, so this widget
  /// listens either way.
  final TextEditingController? controller;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Sits after the clear button — a progress spinner while a remote lookup
  /// is in flight, for the callers that have one.
  final Widget? trailing;

  /// Opens the card scanner from inside the field.
  ///
  /// Web puts the camera *in* the search box and swaps it for the clear
  /// button once there is something to clear (`navbar.tsx`: the `value ? X :
  /// Camera` branch), so the right edge only ever holds one control. Null on
  /// the fields that have no scanner to offer, which is most of them.
  final VoidCallback? onScan;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _owned;

  TextEditingController get _controller =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onTextChanged);
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    // Only the listener comes off a borrowed controller; disposing one the
    // caller owns would break it out from under them.
    _controller.removeListener(_onTextChanged);
    _owned?.dispose();
    super.dispose();
  }

  /// Redraws for the clear button appearing and disappearing.
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 18, color: context.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              style: AppTypography.bodySm(colors.onSurface),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                // Everything off: the shape is the container's job, and the
                // shared form decoration would draw a second field inside it.
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hintText,
                hintStyle: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
          ),
          // One control on the right, never two: clear while there is a
          // query, the scanner when the field is empty.
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
              icon: const Icon(LucideIcons.x, size: 16),
              color: context.mutedForeground,
              visualDensity: VisualDensity.compact,
              tooltip: 'Hapus',
            )
          else if (widget.onScan case final onScan?)
            _ScanAction(onPressed: onScan),
          if (widget.trailing case final trailing?) trailing,
        ],
      ),
    );
  }
}

/// The camera that sits at the right edge of the field.
///
/// A bordered disc on the card surface rather than a bare glyph, matching
/// web's `size-8 rounded-full border border-border bg-card` — it has to read
/// as a button against the field's own fill, which is the same muted tone.
class _ScanAction extends StatelessWidget {
  const _ScanAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      label: 'Pindai kartu',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            shape: BoxShape.circle,
            border: Border.all(color: context.borderColor),
          ),
          child: Icon(LucideIcons.camera, size: 16, color: colors.onSurface),
        ),
      ),
    );
  }
}
