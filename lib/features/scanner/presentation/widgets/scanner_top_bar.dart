import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';

/// Ports `ScannerTopBar` — close, the Bahasa toggle, and the torch.
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
    required this.torchSupported,
    required this.torchOn,
    required this.onToggleTorch,
    required this.onClose,
  });

  final CardLanguage language;
  final ValueChanged<CardLanguage> onLanguageChanged;

  /// Locks the toggle while a capture is in flight — switching language
  /// mid-request would mislabel whatever comes back.
  final bool busy;

  final bool torchSupported;
  final bool torchOn;
  final VoidCallback onToggleTorch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        children: [
          _CircleButton(icon: Icons.close, onTap: onClose, label: 'Tutup'),
          const Spacer(),
          _LanguageToggle(
            language: language,
            enabled: !busy,
            onChanged: onLanguageChanged,
          ),
          const Spacer(),
          if (torchSupported)
            _CircleButton(
              icon: torchOn ? Icons.flashlight_on : Icons.flashlight_off,
              onTap: onToggleTorch,
              label: 'Senter',
              active: torchOn,
            )
          else
            const SizedBox(width: 40),
        ],
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

  final CardLanguage language;
  final bool enabled;
  final ValueChanged<CardLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in CardLanguage.values)
              GestureDetector(
                onTap: enabled && option != language
                    ? () => onChanged(option)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: option == language
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    option.shortLabel,
                    style: AppTypography.captionSemibold(
                      option == language ? Colors.black : Colors.white70,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
