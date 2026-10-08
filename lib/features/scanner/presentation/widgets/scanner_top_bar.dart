import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';

/// Ports `ScannerTopBar` — back, then pause / torch / sound in one group on
/// the left, and the language toggle on the right. Layout, grouping and icons
/// follow web's `ScannerControls.tsx`.
///
/// The language toggle sits here, permanently visible on the scan screen
/// itself, because it carries more weight than its size suggests: it is the
/// mechanism that assigns print language to every card scanned while it's set.
/// Visual recognition cannot separate an Indonesian print from its English
/// reprint (same art, same script), so the human declares it — and the PRD is
/// explicit that this is a live control, flippable mid-batch when the user
/// moves from one binder to the next, not a setting fixed when the session
/// starts.
class ScannerTopBar extends StatelessWidget {
  const ScannerTopBar({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.busy,
    required this.paused,
    required this.onTogglePause,
    required this.torchSupported,
    required this.torchOn,
    required this.onToggleTorch,
    required this.soundOn,
    required this.onToggleSound,
    required this.onClose,
  });

  final CardLanguage language;
  final ValueChanged<CardLanguage> onLanguageChanged;

  /// Locks the toggle while a capture is in flight — switching language
  /// mid-request would mislabel whatever comes back.
  final bool busy;

  final bool paused;
  final VoidCallback onTogglePause;
  final bool torchSupported;
  final bool torchOn;
  final VoidCallback onToggleTorch;
  final bool soundOn;
  final VoidCallback onToggleSound;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Positioned(
      top: padding.top + 12,
      left: padding.left + 12,
      right: padding.right + 12,
      child: Row(
        children: [
          _Glass(
            child: _IconButton(
              icon: LucideIcons.arrowLeft,
              label: 'Kembali',
              onTap: onClose,
            ),
          ),
          const SizedBox(width: 8),
          _Glass(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconButton(
                  icon: paused ? LucideIcons.play : LucideIcons.pause,
                  label: paused ? 'Lanjutkan pemindaian' : 'Jeda pemindaian',
                  onTap: onTogglePause,
                ),
                const SizedBox(width: 4),
                // Disabled rather than hidden, as on web: the group keeps its
                // shape on devices without a torch.
                _IconButton(
                  icon: torchOn ? LucideIcons.zap : LucideIcons.zapOff,
                  label: torchOn ? 'Matikan senter' : 'Nyalakan senter',
                  onTap: torchSupported ? onToggleTorch : null,
                  active: torchOn,
                ),
                const SizedBox(width: 4),
                _IconButton(
                  icon: soundOn ? LucideIcons.volume2 : LucideIcons.volumeX,
                  label: soundOn ? 'Matikan suara' : 'Nyalakan suara',
                  onTap: onToggleSound,
                ),
              ],
            ),
          ),
          const Spacer(),
          _LanguageToggle(
            language: language,
            enabled: !busy,
            onChanged: onLanguageChanged,
          ),
        ],
      ),
    );
  }
}

/// Web's `rounded-full bg-black/40 p-1 backdrop-blur-md`.
class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(4),
          color: Colors.black.withValues(alpha: 0.4),
          child: child,
        ),
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.language,
    required this.enabled,
    required this.onChanged,
  });

  /// Fixed so the white indicator can slide between options by index, the
  /// way web's GSAP indicator does.
  static const _optionWidth = 44.0;

  final CardLanguage language;
  final bool enabled;
  final ValueChanged<CardLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = CardLanguage.values;
    const gap = 4.0;
    final index = options.indexOf(language);
    return _Glass(
      child: SizedBox(
        height: 36,
        width: options.length * _optionWidth + (options.length - 1) * gap,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              left: index * (_optionWidth + gap),
              top: 0,
              bottom: 0,
              width: _optionWidth,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
            Row(
              children: [
                for (final (i, option) in options.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Opacity(
                    opacity: enabled ? 1 : 0.5,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled && option != language
                          ? () => onChanged(option)
                          : null,
                      child: SizedBox(
                        width: _optionWidth,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 160),
                            style: AppTypography.captionSemibold(
                              option == language
                                  ? const Color(0xFF171717)
                                  : Colors.white70,
                            ),
                            child: Text(option.shortLabel),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;

  /// Null disables the button and dims it to web's `text-white/30`.
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active && enabled ? Colors.white : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: !enabled
                ? Colors.white30
                : active
                ? const Color(0xFF171717)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}
