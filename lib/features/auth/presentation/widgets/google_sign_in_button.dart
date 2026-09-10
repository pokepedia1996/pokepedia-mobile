import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// Ports `components/auth/social-buttons.tsx` — the "atau" rule and the
/// Google button beneath it.
class SocialButtons extends StatelessWidget {
  const SocialButtons({
    super.key,
    required this.onGooglePressed,
    this.onApplePressed,
    this.mode = SocialButtonsMode.login,
    this.loading = false,
    this.appleLoading = false,
  });

  /// Null disables the button — a caller that is busy with the email form
  /// passes null rather than a no-op, so the control looks as dead as it is.
  final VoidCallback? onGooglePressed;

  /// Apple's sheet. Null on Android, where the button isn't shown at all —
  /// Apple's own flow there is a browser redirect, which this app avoids.
  final VoidCallback? onApplePressed;

  final SocialButtonsMode mode;
  final bool loading;
  final bool appleLoading;

  /// Apple requires the button wherever a third-party social login is
  /// offered (App Store guideline 4.8), and only iOS can serve it natively.
  ///
  /// `defaultTargetPlatform` rather than `Platform.isIOS`: the latter reports
  /// the *host* under `flutter test`, which would leave this branch
  /// unreachable in a widget test. Both answer iOS on a real device.
  bool get _showApple =>
      defaultTargetPlatform == TargetPlatform.iOS && onApplePressed != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        _OrDivider(),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: loading ? null : onGooglePressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const _GoogleMark(),
              const SizedBox(width: 10),
              // Flexible because the signup label ("Daftar dengan Google") is
              // wider than the login one and overflowed the row on a narrow
              // card. Shrinking beats a yellow-and-black overflow stripe.
              Flexible(
                child: Text(
                  mode == SocialButtonsMode.login
                      ? 'Masuk dengan Google'
                      : 'Daftar dengan Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(
                    context.appColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showApple) ...[
          const SizedBox(height: 10),
          _AppleButton(
            mode: mode,
            loading: appleLoading,
            onPressed: loading ? null : onApplePressed,
          ),
        ],
      ],
    );
  }
}

/// Apple's button, in the black-on-white treatment their Human Interface
/// Guidelines allow. The mark and wording are theirs to specify, so neither
/// follows the app's own palette.
class _AppleButton extends StatelessWidget {
  const _AppleButton({
    required this.mode,
    required this.loading,
    required this.onPressed,
  });

  final SocialButtonsMode mode;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Fixed black/white either way: Apple's guidelines don't allow recolouring
    // the mark to match a theme.
    const foreground = Colors.white;

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: foreground,
        disabledBackgroundColor: Colors.black54,
        minimumSize: const Size.fromHeight(48),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else
            const Icon(Icons.apple, size: 20, color: foreground),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              mode == SocialButtonsMode.login
                  ? 'Masuk dengan Apple'
                  : 'Daftar dengan Apple',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(foreground),
            ),
          ),
        ],
      ),
    );
  }
}

enum SocialButtonsMode { login, signup }

/// A hairline with "atau" knocked out of the middle.
class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(
        height: 1,
        color: context.borderColor.withValues(alpha: 0.6),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ATAU',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ),
        line,
      ],
    );
  }
}

/// Google's four-colour G. Same paths the web button uses, so the two
/// surfaces show an identical mark.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    // Fixed brand colours: the mark stays the same on either theme, which is
    // what Google's branding requires.
    return SvgPicture.string(_svg, width: 18, height: 18);
  }
}
