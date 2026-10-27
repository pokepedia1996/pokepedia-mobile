import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/design_palette.dart';
import '../../../shared/widgets/setup_kit.dart';
import '../../market/usecase/market_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../usecase/onboarding_intents.dart';

/// `profiles_username_format`: `^[a-zA-Z0-9_]{3,20}$`. The unique index
/// still has the final say; this only spares a bad name a round trip.
final _usernameFormat = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
const _usernameMin = 3;
const _usernameMax = 20;

/// How long to sit on a keystroke before asking the server, as on the web.
const _checkDebounce = Duration(milliseconds: 400);

/// Where onboarding sends the user once it is done. The router itself, not
/// a `BuildContext`: onboarding sits above the router's Navigator, with no
/// route below it to push from. A provider so tests can see where it went.
final onboardingLandingProvider = Provider<void Function(String route)>(
  (ref) => appRouter.go,
);

/// Shows [OnboardingPage] over whatever is on screen once the signed-in
/// user turns out not to have finished onboarding. Mounted from
/// `MaterialApp.router`'s builder, so it covers pushed routes and shell tabs
/// alike: a social sign-in can land on any screen, and the username is owed
/// either way.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    // Only an explicit false opens it: null means the profile row hasn't
    // landed yet, and guessing would flash onboarding over every launch.
    final show = user != null && user.onboarded == false;

    return Stack(
      children: [
        child,
        // Its own Overlay: `MaterialApp.builder` runs above the router's
        // Navigator, so this subtree sits outside the app's Overlay, and a
        // TextField needs one to place its selection handles and toolbar.
        if (show)
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(builder: (_) => const OnboardingPage()),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the availability check says about the typed name.
///
/// [unverifiable] is not [taken]: the RPC failing is not an answer, and
/// there is no way past onboarding but a name. Treating "could not ask" as
/// "no" would lock someone out of the app.
enum _NameState { idle, tooShort, checking, available, taken, unverifiable }

/// A new account's two steps: a username (`handle_new_user` writes every
/// profile without one, and no sign-in asks), then what they came to do,
/// which only decides where they land and what Beranda offers.
///
/// Nothing is written until the end. Step 2 can go back and change the
/// name, and the name is claimed once, with the onboarded flag, by
/// [AuthNotifier.completeOnboarding].
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = TextEditingController();

  int _step = 0;
  Timer? _debounce;
  _NameState _nameState = _NameState.idle;

  /// Names offered under the field, already checked free.
  List<String> _suggestions = const [];

  /// Runtime starts with nothing picked; the design's ticks are an example.
  final _picked = <OnboardingIntent>{};
  bool _submitting = false;

  /// Why finishing failed, shown above the step-2 buttons.
  String? _finishError;

  String get _username => _controller.text.trim();

  bool get _canContinue =>
      _usernameFormat.hasMatch(_username) &&
      (_nameState == _NameState.available ||
          _nameState == _NameState.unverifiable);

  @override
  void initState() {
    super.initState();
    _seedFromAccount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Google and Apple hand back a name, and every account has an email.
  /// The first that makes a legal username is offered in the field, with a
  /// few variations of it as suggestions.
  ///
  /// Guarded end to end: a convenience on top of a step the user can finish
  /// by typing, so nothing here may throw into the first frame.
  void _seedFromAccount() {
    String? base;
    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final metadata = user?.userMetadata;
      for (final candidate in [
        metadata?['display_name'],
        metadata?['full_name'],
        metadata?['name'],
        user?.email?.split('@').first,
      ]) {
        base = usernameBase(candidate is String ? candidate : null);
        if (base != null) break;
      }
    } catch (_) {
      base = null;
    }
    if (base == null) return;

    _controller.text = base;
    _onChanged(base);
    unawaited(_loadSuggestions(base));
  }

  /// Keeps the suggestions that are free. A check that could not be made
  /// leaves its name out: a chip is an offer, and offering a taken name
  /// would be worse than offering fewer.
  Future<void> _loadSuggestions(String base) async {
    final users = ref.read(userRepositoryProvider);
    final candidates = usernameSuggestions(base, year: DateTime.now().year);
    final answers = await Future.wait(
      candidates.map(users.isUsernameAvailable),
    );
    if (!mounted) return;
    setState(() {
      _suggestions = [
        for (var i = 0; i < candidates.length; i++)
          if (answers[i] == true) candidates[i],
      ];
    });
  }

  void _onChanged(String raw) {
    final value = raw.trim();
    _debounce?.cancel();
    setState(() {
      _finishError = null;
      _nameState = value.isEmpty
          ? _NameState.idle
          : value.length < _usernameMin
          ? _NameState.tooShort
          : _NameState.checking;
    });
    if (_nameState != _NameState.checking) return;
    _debounce = Timer(_checkDebounce, () => _check(value));
  }

  Future<void> _check(String value) async {
    final available = await ref
        .read(userRepositoryProvider)
        .isUsernameAvailable(value);
    if (!mounted) return;
    // A later keystroke moved on; the check it scheduled owns the state.
    if (_username != value) return;
    setState(() {
      _nameState = available == null
          ? _NameState.unverifiable
          : available
          ? _NameState.available
          : _NameState.taken;
    });
  }

  void _useSuggestion(String name) {
    _controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _onChanged(name);
  }

  void _toStep(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _finishError = null;
    });
  }

  /// Claims the name, keeps the picks, and lands where the first pick
  /// points — Beranda when nothing was picked or the step was skipped.
  Future<void> _finish({required bool skipped}) async {
    if (_submitting) return;
    final intents = skipped
        ? const <OnboardingIntent>[]
        : OnboardingIntent.ordered(_picked);
    setState(() {
      _submitting = true;
      _finishError = null;
    });

    await ref.read(onboardingIntentsProvider.notifier).save(intents);
    final error = await ref
        .read(authProvider.notifier)
        .completeOnboarding(_username);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        if (error == 'Username sudah dipakai') {
          // Taken since it was checked: back to where it can be changed.
          _nameState = _NameState.taken;
          _step = 0;
        } else {
          _finishError = error;
        }
      });
      return;
    }

    final landing = intents.isEmpty ? null : intents.first;
    if (landing == OnboardingIntent.bid) {
      ref.read(marketWtbTipProvider.notifier).state = true;
    }
    // On success the profile reloads onboarded and the gate takes this page
    // down.
    ref.read(onboardingLandingProvider)(landing?.route ?? Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);

    return PopScope(
      // Only the second step has somewhere to go back to.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1 && !_submitting) _toStep(0);
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: _step == 0 ? _usernameStep(palette) : _intentStep(palette),
          ),
        ),
      ),
    );
  }

  Widget _usernameStep(DesignPalette palette) {
    final value = _username;
    return Column(
      key: const ValueKey('step-username'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SetupProgress(
                  step: 0,
                  total: 2,
                  palette: palette,
                  showBack: false,
                ),
                const SizedBox(height: 28),
                _Intro(
                  first: 'Pilih',
                  second: 'username kamu.',
                  sub:
                      'Ini nama profilmu di pokepedia. Nama toko bisa beda, '
                      'atur nanti.',
                  palette: palette,
                ),
                const SizedBox(height: 28),
                _ProfilePreview(username: value, palette: palette),
                const SizedBox(height: 28),
                _UsernameField(
                  controller: _controller,
                  state: _nameState,
                  onChanged: _onChanged,
                  onSubmitted: () {
                    if (_canContinue) _toStep(1);
                  },
                  palette: palette,
                ),
                if (_suggestions.any((s) => s != value)) ...[
                  const SizedBox(height: 28),
                  _Suggestions(
                    names: [
                      for (final s in _suggestions)
                        if (s != value) s,
                    ],
                    onPick: _useSuggestion,
                    palette: palette,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        SetupPrimaryButton(
          label: 'Lanjut',
          onPressed: _canContinue ? () => _toStep(1) : null,
          palette: palette,
        ),
        const SizedBox(height: 12),
        Text(
          'Huruf, angka & garis bawah. $_usernameMin–$_usernameMax karakter.',
          textAlign: TextAlign.center,
          style: setupText(12, palette.muted),
        ),
      ],
    );
  }

  Widget _intentStep(DesignPalette palette) {
    return Column(
      key: const ValueKey('step-intents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SetupProgress(
                  step: 1,
                  total: 2,
                  palette: palette,
                  onBack: _submitting ? null : () => _toStep(0),
                ),
                const SizedBox(height: 28),
                _Intro(
                  first: 'Mau ngapain',
                  second: 'di pokepedia?',
                  sub:
                      'Pilih satu atau lebih. Kami siapkan jalan pintasnya '
                      'buat kamu.',
                  palette: palette,
                ),
                const SizedBox(height: 28),
                for (final intent in OnboardingIntent.values) ...[
                  _IntentOption(
                    intent: intent,
                    selected: _picked.contains(intent),
                    onTap: _submitting
                        ? null
                        : () => setState(() {
                            if (!_picked.remove(intent)) _picked.add(intent);
                          }),
                    palette: palette,
                  ),
                  if (intent != OnboardingIntent.values.last)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (_finishError != null) ...[
          Text(
            _finishError!,
            textAlign: TextAlign.center,
            style: setupText(13, palette.error, FontWeight.w500),
          ),
          const SizedBox(height: 12),
        ],
        SetupPrimaryButton(
          label: 'Mulai jelajah',
          busy: _submitting,
          onPressed: _submitting ? null : () => _finish(skipped: false),
          palette: palette,
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: _submitting ? null : () => _finish(skipped: true),
            style: TextButton.styleFrom(foregroundColor: palette.muted),
            child: Text(
              'Lewati dulu',
              style: setupText(14, palette.muted, FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// The name a username would be built from: lower case, anything the
/// format refuses turned into an underscore, and cut to the maximum. Null
/// when too little of it survives.
@visibleForTesting
String? usernameBase(String? source) {
  if (source == null) return null;
  var base = source
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (base.length > _usernameMax) base = base.substring(0, _usernameMax);
  return base.length >= _usernameMin ? base : null;
}

/// Variations on [base] to offer when it is taken, or just as options:
/// `mulyana_tcg`, `mulyana_26`, `binder_mulyana`. Each fits the format,
/// cutting [base] rather than the suffix, which is the part that makes it
/// read as a variation.
@visibleForTesting
List<String> usernameSuggestions(String base, {required int year}) {
  String fit(String prefix, String suffix) {
    final room = _usernameMax - prefix.length - suffix.length;
    final cut = base.length > room ? base.substring(0, room) : base;
    return '$prefix$cut$suffix';
  }

  final yy = (year % 100).toString().padLeft(2, '0');
  return [fit('', '_tcg'), fit('', '_$yy'), fit('binder_', '')];
}

/// The two-line headline, its second line in the brand colour, and the
/// line under it.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.first,
    required this.second,
    required this.sub,
    required this.palette,
  });

  final String first;
  final String second;
  final String sub;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupHeadline(first: first, second: second, palette: palette),
        const SizedBox(height: 10),
        Text(
          sub,
          style: setupText(15, palette.muted, FontWeight.w400, 22 / 15),
        ),
      ],
    );
  }
}

/// How the profile will read, updating as the name is typed.
class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.username, required this.palette});

  final String username;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    final empty = username.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              empty ? '?' : username[0].toUpperCase(),
              style: setupHeading(22, palette.brand),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              empty ? '@username' : '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: setupText(
                16,
                empty ? palette.muted : palette.ink,
                FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Pratinjau',
            style: setupText(11, palette.muted, FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.state,
    required this.onChanged,
    required this.onSubmitted,
    required this.palette,
  });

  final TextEditingController controller;
  final _NameState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    final (border, borderWidth) = switch (state) {
      _NameState.available => (palette.success, 1.5),
      _NameState.taken || _NameState.tooShort => (palette.error, 1.5),
      _ => (palette.border, 1.0),
    };
    final (hint, hintColor) = switch (state) {
      _NameState.available => (
        'Mantap, username ini tersedia!',
        palette.successText,
      ),
      _NameState.taken => ('Username sudah dipakai', palette.error),
      _NameState.tooShort => ('Minimal $_usernameMin karakter.', palette.error),
      _NameState.checking => ('Memeriksa ketersediaan...', palette.muted),
      _NameState.unverifiable => (
        'Tidak bisa memeriksa ketersediaan. Kamu tetap bisa lanjut.',
        palette.muted,
      ),
      _NameState.idle => (null, palette.muted),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Username', style: setupText(13, palette.ink, FontWeight.w600)),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: border, width: borderWidth),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text('@', style: setupText(17, palette.muted)),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitted(),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  // The format, enforced as typed: nothing it refuses gets
                  // in, and nothing past its length.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(_usernameMax),
                  ],
                  cursorColor: palette.brand,
                  style: setupText(17, palette.ink, FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'username_kamu',
                    hintStyle: setupText(
                      17,
                      palette.muted.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              switch (state) {
                _NameState.checking => SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.muted,
                  ),
                ),
                _NameState.available => Icon(
                  LucideIcons.circleCheck,
                  size: 20,
                  color: palette.success,
                ),
                _NameState.taken => Icon(
                  LucideIcons.circleX,
                  size: 20,
                  color: palette.error,
                ),
                _ => const SizedBox.shrink(),
              },
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 10),
          Text(hint, style: setupText(13, hintColor, FontWeight.w500)),
        ],
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.names,
    required this.onPick,
    required this.palette,
  });

  final List<String> names;
  final ValueChanged<String> onPick;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Atau pakai saran ini', style: setupText(13, palette.muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in names)
              Material(
                color: palette.chip,
                shape: StadiumBorder(side: BorderSide(color: palette.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onPick(name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      '@$name',
                      style: setupText(13, palette.ink, FontWeight.w500),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One "Mau ngapain?" option: ticked, it takes the brand outline, a tinted
/// icon and a filled check.
class _IntentOption extends StatelessWidget {
  const _IntentOption({
    required this.intent,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final OnboardingIntent intent;
  final bool selected;
  final VoidCallback? onTap;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? palette.brand : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? palette.brandSoft : palette.chip,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    intent.icon,
                    size: 22,
                    color: selected ? palette.brand : palette.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intent.title,
                        style: setupText(16, palette.ink, FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        intent.description,
                        style: setupText(13, palette.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SetupCheckIndicator(selected: selected, palette: palette),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
