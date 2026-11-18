import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'onb_style.dart';

/// Back: a 36 circle in 6% ink, an 18 arrow.
class OnbRoundBack extends StatelessWidget {
  const OnbRoundBack({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Kembali',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0x0F1C1413),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.arrowLeft, size: 18, color: onbInk),
        ),
      ),
    );
  }
}

/// The dark CTA: 54 tall, label 16/800, an 18 arrow 8 away. It dips to 0.98
/// while pressed, greys out when [onTap] is null, and shows a spinner while
/// [busy]. [labelOpacity] and [labelDy] let the label cross over.
class OnbCta extends StatefulWidget {
  const OnbCta({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.labelOpacity = 1,
    this.labelDy = 0,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final double labelOpacity;
  final double labelDy;

  @override
  State<OnbCta> createState() => _OnbCtaState();
}

class _OnbCtaState extends State<OnbCta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.busy;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.busy ? null : widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 54,
            decoration: BoxDecoration(
              color: enabled ? onbInk : onbDisabled,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: widget.labelOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, widget.labelDy),
                          child: Text(
                            widget.label,
                            style: onbBody(16, Colors.white, FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        LucideIcons.arrowRight,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
