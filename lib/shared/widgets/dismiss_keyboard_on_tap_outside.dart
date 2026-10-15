import 'package:flutter/widgets.dart';

/// Drops focus — and with it the keyboard — when a tap lands outside the
/// focused text field, the way native iOS and Android apps behave.
///
/// Flutter's default only does this for a mouse or stylus: on a phone a
/// touch outside leaves the field focused, and iOS has no back key, so a
/// keyboard summoned by `autofocus` could only be closed by quitting the app.
///
/// Overrides the [EditableTextTapOutsideIntent] every field raises rather
/// than wrapping the app in a [GestureDetector], so it never competes with
/// buttons in the gesture arena. A tap on another field isn't "outside" —
/// fields share one tap region group — so focus moves without the keyboard
/// flickering. A field's own `onTapOutside` still takes precedence.
class DismissKeyboardOnTapOutside extends StatelessWidget {
  const DismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: child,
    );
  }
}
