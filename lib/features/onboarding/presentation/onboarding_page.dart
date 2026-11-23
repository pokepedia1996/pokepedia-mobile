import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/coretan_kit.dart';
import '../../../shared/widgets/scribble_drawing.dart';
import '../../market/usecase/market_notifier.dart';
import '../../referral/usecase/pending_referral.dart';
import '../../referral/usecase/referral_providers.dart';
import '../../user/usecase/user_notifier.dart';
import '../usecase/onboarding_intents.dart';
import 'onb_style.dart';
import 'onb_widgets.dart';

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

/// [referralCodeShape], under the name this page has always used.
final _referralShape = referralCodeShape;

/// What the availability check says about the typed name.
///
/// [unverifiable] is not [taken]: the RPC failing is not an answer, and
/// there is no way past onboarding but a name. Treating "could not ask" as
/// "no" would lock someone out of the app.
enum _NameState {
  idle,
  badChars,
  tooShort,
  checking,
  available,
  taken,
  unverifiable,
}

/// What `validate_referral_code` says about the typed code. [unknown] is the
/// call failing: the field is optional, so it just stays quiet.
enum _CodeState { idle, checking, valid, rejected, unknown }

/// A new account's two steps: a username (`handle_new_user` writes every
/// profile without one, and no sign-in asks), then what they came to do,
/// which only decides where they land and what Beranda offers.
///
/// Geometry is `pokepad.pen` "Onboarding Baru 7 · 8" at its own pixel
/// values; the motion is the prototype's `goView()` and `staggerIn()`: the
/// page pushes in over 560 ms while the old one slides 26% away, and the
/// blocks rise in behind it, 45 ms apart.
///
/// Nothing is written until the end. Step 2 can go back and change the
/// name, and the name is claimed once, with the onboarded flag, by
/// [AuthNotifier.completeOnboarding].
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _codeController = TextEditingController();
  final _rewardKey = GlobalKey();

  /// The page push: 560 ms, `push` curve.
  late final _push = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  /// The blocks rising in: the last of seven starts at 200 + 6·45 ms and
  /// takes 480.
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  int _step = 0;

  /// The step being left while a push runs; -1 when none is, or when the
  /// whole flow is sliding in over the app for the first time.
  int _from = -1;
  bool _entering = true;

  /// Whether the blocks of [_revealStep] rise in. Going back does not
  /// replay them, nor the drawings.
  bool _stagger = true;
  int _revealStep = 0;
  bool _started = false;

  Timer? _debounce;
  Timer? _codeDebounce;

  /// The code check in flight, so Lanjut waits on it instead of asking the
  /// server (and spending a call of the 20 a minute) a second time.
  Future<void>? _codeCheck;
  _CodeState _codeState = _CodeState.idle;
  String? _referrer;
  String? _codeMessage;

  /// The code already applied, so going back and forward does not spend
  /// another of the server's 20 calls a minute on it.
  String? _appliedCode;
  bool _continuing = false;
  _NameState _nameState = _NameState.idle;

  /// Names offered under the field, already checked free.
  List<String> _suggestions = const [];

  /// Runtime starts with nothing picked; the design's ticks are an example.
  final _picked = <OnboardingIntent>{};
  bool _submitting = false;

  /// Why finishing failed, shown above the step-2 buttons.
  String? _finishError;

  String get _username => _controller.text.trim();
  String get _code => _codeController.text.trim().toUpperCase();

  bool get _canContinue =>
      _usernameFormat.hasMatch(_username) &&
      (_nameState == _NameState.available ||
          _nameState == _NameState.unverifiable);

  @override
  void initState() {
    super.initState();
    _seedFromAccount();
    PendingReferral.code.addListener(_takeInviteCode);
    _takeInviteCode();
  }

  /// A code from a tapped invite link (`/r/<code>`) fills the field when it
  /// is empty, and is checked like a typed one. Also while this page is
  /// open: the link can be tapped with onboarding already showing.
  void _takeInviteCode() {
    final code = PendingReferral.code.value;
    if (code == null || _codeController.text.trim().isNotEmpty) return;
    _codeController.text = code;
    // `_onCodeChanged` sets state, which the first build does not allow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onCodeChanged(code);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (coretanReduceMotion(context)) {
      _push.value = 1;
      _reveal.value = 1;
      _entering = false;
      return;
    }
    // The flow slides in from the right over whatever was on screen, and
    // its blocks rise behind it.
    _push.forward().whenComplete(() {
      if (mounted) setState(() => _entering = false);
    });
    _reveal.forward();
  }

  @override
  void dispose() {
    PendingReferral.code.removeListener(_takeInviteCode);
    _debounce?.cancel();
    _codeDebounce?.cancel();
    _controller.dispose();
    _codeController.dispose();
    _push.dispose();
    _reveal.dispose();
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
          : !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)
          ? _NameState.badChars
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

  void _onCodeChanged(String raw) {
    final code = raw.trim().toUpperCase();
    _codeDebounce?.cancel();
    final asks = _referralShape.hasMatch(code);
    setState(() {
      _codeState = asks ? _CodeState.checking : _CodeState.idle;
      _referrer = null;
      _codeMessage = null;
    });
    if (asks) _codeDebounce = Timer(_checkDebounce, () => _checkCode(code));
  }

  Future<void> _checkCode(String code) {
    final run = _runCodeCheck(code);
    _codeCheck = run;
    return run.whenComplete(() {
      if (identical(_codeCheck, run)) _codeCheck = null;
    });
  }

  Future<void> _runCodeCheck(String code) async {
    ReferralCheck? check;
    try {
      check = await ref.read(referralRepositoryProvider).validateCode(code);
    } catch (_) {
      check = null;
    }
    if (!mounted || _code != code) return;
    setState(() {
      if (check == null) {
        _codeState = _CodeState.unknown;
      } else if (check.valid) {
        _codeState = _CodeState.valid;
        _referrer = check.referrerUsername;
      } else {
        _codeState = _CodeState.rejected;
        _codeMessage = check.fieldMessage;
      }
    });
    if (_codeState == _CodeState.valid) {
      // If the card landed under the footer, bring it into view.
      Future.delayed(const Duration(milliseconds: 120), _revealReward);
    }
  }

  void _revealReward() {
    final ctx = _rewardKey.currentContext;
    if (!mounted || ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: onbOut,
    );
  }

  /// Step 1 → 2. A valid code is applied here, while the account is fresh
  /// (the server only takes it in the first days, before any order). A code
  /// that will not apply never blocks onboarding: it says so and moves on.
  Future<void> _continueFromUsername() async {
    if (_continuing || !_canContinue) return;
    final code = _code;
    final asks = _referralShape.hasMatch(code);
    // Tapped while the code is still being (re)checked: ask now rather than
    // let a good code slip past unapplied.
    final pending =
        asks &&
        (_codeState == _CodeState.idle || _codeState == _CodeState.checking);
    if (!pending && !(_codeState == _CodeState.valid && _appliedCode != code)) {
      _toStep(1);
      return;
    }
    setState(() => _continuing = true);
    if (pending) {
      _codeDebounce?.cancel();
      await (_codeCheck ?? _checkCode(code));
      if (!mounted) return;
    }
    var applied = false;
    if (_codeState == _CodeState.valid && _code == code) {
      try {
        applied =
            (await ref.read(referralRepositoryProvider).applyCode(code)).ok;
      } catch (_) {}
      if (!mounted) return;
    }
    setState(() => _continuing = false);
    if (applied) {
      _appliedCode = code;
      unawaited(PendingReferral.clear());
    } else if (_codeState == _CodeState.valid) {
      // A rejected or unknown code was already said under the field; only a
      // valid one that then would not apply needs telling here.
      _say('Kode referal tidak bisa dipakai');
    }
    _toStep(1);
  }

  /// A line at the foot of the page, in the paper's own colours: the app's
  /// messenger sits above this page's locked light theme.
  void _say(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        backgroundColor: onbInk,
        content: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  /// A push to [step]: the new page slides in over 560 ms while the old
  /// one goes 26% away; going back is the same the other way round. Only
  /// going forward replays the blocks rising in.
  void _toStep(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (step == _step) return;
    final forward = step > _step;
    if (coretanReduceMotion(context)) {
      setState(() {
        _step = step;
        _finishError = null;
      });
      return;
    }
    setState(() {
      _from = _step;
      _step = step;
      _entering = false;
      _stagger = forward;
      _revealStep = step;
      _finishError = null;
    });
    _push.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _from = -1);
    });
    if (forward) {
      _reveal.forward(from: 0);
    } else {
      _reveal.value = 1;
    }
  }

  /// Back on step 1 leaves the account: they are already signed in, so
  /// "back to Daftar" means signing out. Asked first.
  Future<void> _askSignOut() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final leave = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (leave == true) await ref.read(authProvider.notifier).signOut();
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

    try {
      await ref.read(onboardingIntentsProvider.notifier).save(intents);
    } catch (_) {
      // The local copy only feeds Beranda's shortcuts; the server write
      // below is what counts, and it must not be held up by this.
    }
    final error = await ref
        .read(authProvider.notifier)
        .completeOnboarding(
          _username,
          intents: [for (final intent in intents) intent.raw],
        );
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        if (error == 'Username sudah dipakai') {
          // Taken since it was checked: back to where it can be changed.
          _nameState = _NameState.taken;
          _step = 0;
          _from = -1;
        } else {
          _finishError = error;
        }
      });
      return;
    }

    // Applied or not, an invite code has no use past onboarding.
    unawaited(PendingReferral.clear());
    final landing = intents.isEmpty ? null : intents.first;
    if (landing == OnboardingIntent.bid) {
      ref.read(marketWtbTipProvider.notifier).state = true;
    }
    // On success the profile reloads onboarded and the gate takes this page
    // down.
    ref.read(onboardingLandingProvider)(landing?.route ?? Routes.home);
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // The paper and its ink are light only.
    return Theme(
      data: AppTheme.light,
      child: Builder(builder: _scaffold),
    );
  }

  Widget _scaffold(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || _submitting) return;
            _step == 1 ? _toStep(0) : _askSignOut();
          },
          child: Scaffold(
            backgroundColor: AppColors.onbCream,
            body: ClipRect(
              child: AnimatedBuilder(
                animation: Listenable.merge([_push, _reveal]),
                builder: (context, _) => _pages(size.width),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The page on screen, or two of them mid-push: the new one slides in
  /// from the right (or the old one slides out to it), the other drifts 26%
  /// of the width the opposite way.
  Widget _pages(double width) {
    final pushing = _entering || _from >= 0;
    if (!pushing) return _shell(_page(_step), shadow: false);

    final e = onbPush.transform(_push.value);
    final forward = _from < 0 || _step > _from;
    if (_from < 0) {
      // Over the app for the first time: only the new page.
      return Transform.translate(
        offset: Offset(width * (1 - e), 0),
        child: _shell(_page(_step), shadow: true),
      );
    }
    final fresh = Transform.translate(
      offset: Offset(forward ? width * (1 - e) : -0.26 * width * (1 - e), 0),
      child: _shell(_page(_step), shadow: forward),
    );
    final old = Transform.translate(
      offset: Offset(forward ? -0.26 * width * e : width * e, 0),
      child: _shell(_page(_from), shadow: !forward),
    );
    return Stack(
      fit: StackFit.expand,
      children: forward ? [old, fresh] : [fresh, old],
    );
  }

  /// A page's own paper: cream with the energy pattern, and while it slides
  /// the soft shadow along its leading edge.
  Widget _shell(Widget child, {required bool shadow}) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.onbCream,
          image: const DecorationImage(
            image: AssetImage(coretanTileCream),
            repeat: ImageRepeat.repeat,
            // 778 px drawn as 259 pt.
            scale: 3,
            alignment: Alignment.topLeft,
          ),
          boxShadow: shadow
              ? const [
                  BoxShadow(
                    color: Color(0x291C1413),
                    blurRadius: 34,
                    offset: Offset(-14, 0),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }

  Widget _page(int step) {
    final insets = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        math.max(56, insets.top),
        24,
        math.max(28, insets.bottom),
      ),
      child: step == 0 ? _step1() : _step2(),
    );
  }

  /// One block rising in, `k`th of its page, 480 ms after 200 + 45·k.
  Widget _rv(int step, int k, Widget child) {
    if (!_stagger || step != _revealStep) return child;
    final p = onbTrack(_reveal.value * 950, 200.0 + 45 * k, 480, onbOut);
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, 14 * (1 - p)), child: child),
    );
  }

  /// Whether a page is the one whose drawings should draw themselves in.
  bool _drawing(int step) => _stagger && step == _revealStep;

  Widget _topBar(int step) {
    final seg2 = step == 1
        ? (_stagger && _revealStep == 1
              ? onbTrack(_reveal.value * 950, 320, 600, onbOut)
              : 1.0)
        : 0.0;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          OnbRoundBack(
            onTap: _submitting
                ? null
                : step == 0
                ? _askSignOut
                : () => _toStep(0),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Seg(fill: 1),
                  const SizedBox(width: 6),
                  _Seg(fill: seg2),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('${step + 1}/2', style: onbHand(19, onbMuted)),
            ),
          ),
        ],
      ),
    );
  }

  /// The eyebrow, the headline (two lines, the second in red) and the line
  /// under it: 153 tall.
  Widget _teks(String eyebrow, String first, String second, String sub) {
    // 33 a line, as the design's boxes: 31 × 1.08 less its rounding.
    final line = onbHeading(31, onbInk, height: 33 / 31);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 31,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Transform.rotate(
              angle: -2 * math.pi / 180,
              child: Text(eyebrow, style: onbHand(20, onbRed)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(first, style: line),
        Text(second, style: line.copyWith(color: onbRed)),
        const SizedBox(height: 6),
        Text(sub, style: onbBody(15, onbMuted, FontWeight.w400, 1.45)),
      ],
    );
  }

  Widget _step1() {
    final value = _username;
    return Column(
      key: const ValueKey('step-username'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rv(0, 0, _topBar(0)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rv(
                  0,
                  1,
                  _teks(
                    'langkah 1 dari 2',
                    'Pilih',
                    'username kamu.',
                    'Ini nama profilmu di pokepedia. Nama toko bisa beda, '
                        'atur nanti.',
                  ),
                ),
                const SizedBox(height: 18),
                _rv(
                  0,
                  2,
                  _ProfilePreview(username: value, drawIn: _drawing(0)),
                ),
                const SizedBox(height: 18),
                _rv(
                  0,
                  3,
                  _UsernameBlock(
                    controller: _controller,
                    state: _nameState,
                    onChanged: _onChanged,
                    onSubmitted: _continueFromUsername,
                  ),
                ),
                if (_suggestions.any((s) => s != value)) ...[
                  const SizedBox(height: 18),
                  _rv(
                    0,
                    4,
                    _Suggestions(
                      names: [
                        for (final s in _suggestions)
                          if (s != value) s,
                      ],
                      current: value,
                      onPick: _useSuggestion,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _rv(
                  0,
                  5,
                  _ReferralBlock(
                    controller: _codeController,
                    state: _codeState,
                    referrer: _referrer,
                    message: _codeMessage,
                    rewardKey: _rewardKey,
                    onChanged: _onCodeChanged,
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        _rv(
          0,
          6,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OnbCta(
                label: 'Lanjut',
                busy: _continuing,
                onTap: _canContinue ? _continueFromUsername : null,
              ),
              const SizedBox(height: 12),
              Text(
                '$_usernameMin–$_usernameMax karakter: huruf, angka, '
                'garis bawah.',
                textAlign: TextAlign.center,
                style: onbBody(12, onbMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _step2() {
    final options = OnboardingIntent.values;
    return Column(
      key: const ValueKey('step-intents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rv(1, 0, _topBar(1)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rv(
                  1,
                  1,
                  _teks(
                    'langkah 2 dari 2',
                    'Mau ngapain',
                    'di pokepedia?',
                    'Pilih satu atau lebih. Ini bantu kami bikin Pokepedia '
                        'makin pas buat kamu.',
                  ),
                ),
                const SizedBox(height: 18),
                // The list's own 4 above, then 12 between.
                const SizedBox(height: 4),
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _rv(
                    1,
                    2 + i,
                    _Opt(
                      intent: options[i],
                      selected: _picked.contains(options[i]),
                      drawDelay: Duration(milliseconds: 380 + 110 * i),
                      animate: _drawing(1),
                      onTap: _submitting
                          ? null
                          : () => setState(() {
                              if (!_picked.remove(options[i])) {
                                _picked.add(options[i]);
                              }
                            }),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        _rv(
          1,
          6,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_finishError != null) ...[
                Text(
                  _finishError!,
                  textAlign: TextAlign.center,
                  style: onbBody(13, onbRed, FontWeight.w500),
                ),
                const SizedBox(height: 12),
              ],
              OnbCta(
                label: 'Mulai jelajah',
                busy: _submitting,
                onTap: _submitting ? null : () => _finish(skipped: false),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submitting ? null : () => _finish(skipped: true),
                  child: Semantics(
                    button: true,
                    child: Text(
                      'Lewati dulu',
                      style: onbBody(14, onbMuted, FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
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

/// [child] at its own height inside a box the design fixes. A line more than
/// the design has (a larger font, say) spills over rather than failing to
/// lay out.
class _Spill extends StatelessWidget {
  const _Spill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: Alignment.centerLeft,
    minHeight: 0,
    maxHeight: double.infinity,
    child: child,
  );
}

/// A progress segment, 44×8: pale, with red filling it from the left.
class _Seg extends StatelessWidget {
  const _Seg({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 8,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: onbOff,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fill.clamp(0.0, 1.0),
        child: const ColoredBox(color: onbRed),
      ),
    );
  }
}

/// A white box on the paper, 54 tall, in the border colour its state asks
/// for (the colour changes over 250 ms).
class _Box extends StatelessWidget {
  const _Box({required this.border, required this.child});

  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border, width: 1.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// A handwritten line under a field, 24 tall: a new text fades in from 4
/// above over 220 ms.
class _Hint extends StatelessWidget {
  const _Hint(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -4 / 24),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: onbOut)),
            child: child,
          ),
        ),
        child: Text(
          text,
          key: ValueKey('$text$color'),
          style: onbHand(18, color),
        ),
      ),
    );
  }
}

/// The drawn tick at the end of a valid field: it draws itself in, and
/// fades out over 200 ms.
class _Tick extends StatelessWidget {
  const _Tick({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: on
            ? const ScribbleDrawing(
                key: ValueKey('tick'),
                drawing: 'icon_ok',
                stepMs: 40,
                idle: false,
              )
            : const SizedBox.shrink(key: ValueKey('none')),
      ),
    );
  }
}

/// How the profile will read, updating as the name is typed: 76 tall.
class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.username, required this.drawIn});

  final String username;
  final bool drawIn;

  @override
  Widget build(BuildContext context) {
    final empty = username.isEmpty;
    final initial = empty ? '?' : username[0].toUpperCase();
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: onbLine),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ScribbleDrawing(
                  drawing: 'icon_avatar',
                  idle: false,
                  animate: drawIn,
                  delay: const Duration(milliseconds: 320),
                ),
                // A new letter pops in: 0.4 → 1 over 300 ms.
                TweenAnimationBuilder<double>(
                  key: ValueKey(initial),
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 300),
                  curve: onbPop,
                  builder: (context, v, child) => Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.scale(scale: v, child: child),
                  ),
                  child: Text(initial, style: onbHeading(25, onbInk)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Spill(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empty ? '@username' : '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: onbHeading(20, empty ? onbMuted : onbInk),
                  ),
                  const SizedBox(height: 2),
                  Text('pratinjau profilmu', style: onbHand(17, onbRed)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 34,
            height: 40,
            child: ScribbleDrawing(
              drawing: 'icon_kilau',
              idle: false,
              animate: drawIn,
              delay: const Duration(milliseconds: 520),
            ),
          ),
        ],
      ),
    );
  }
}

/// The username field: label, a 54 box, and the handwritten verdict, 110
/// in all.
class _UsernameBlock extends StatelessWidget {
  const _UsernameBlock({
    required this.controller,
    required this.state,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final _NameState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _NameState.available => onbGreen,
      _NameState.taken || _NameState.tooShort || _NameState.badChars => onbRed,
      _ => onbLine,
    };
    final (hint, hintColor) = switch (state) {
      _NameState.idle => ('Isi username dulu, ya.', onbRed),
      _NameState.badChars => (
        'Cuma boleh huruf, angka, dan garis bawah.',
        onbRed,
      ),
      _NameState.tooShort => ('Minimal $_usernameMin karakter.', onbRed),
      _NameState.checking => ('Ngecek dulu…', onbMuted),
      _NameState.available => ('Mantap, username ini tersedia!', onbGreen),
      _NameState.taken => ('Yah, sudah dipakai. Coba saran di bawah.', onbRed),
      _NameState.unverifiable => (
        'Tidak bisa memeriksa ketersediaan. Kamu tetap bisa lanjut.',
        onbMuted,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Username', style: onbBody(13, onbInk, FontWeight.w800)),
        const SizedBox(height: 8),
        _Box(
          border: border,
          child: Row(
            children: [
              Text('@', style: onbBody(16, onbMuted, FontWeight.w700)),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitted(),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  // No spaces, and no more than the database holds; any
                  // other character is said, not silently dropped.
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    LengthLimitingTextInputFormatter(_usernameMax),
                  ],
                  cursorColor: onbRed,
                  style: onbBody(16, onbInk, FontWeight.w700),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'username_kamu',
                    hintStyle: onbBody(16, onbMuted.withValues(alpha: 0.6)),
                  ),
                ),
              ),
              _Tick(on: state == _NameState.available),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Hint(hint, hintColor),
      ],
    );
  }
}

/// "Atau pakai saran ini" over one row of chips, scrolled sideways.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.names,
    required this.current,
    required this.onPick,
  });

  final List<String> names;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Atau pakai saran ini',
          style: onbBody(13, onbMuted, FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: names.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Chip(
              name: names[i],
              active: names[i] == current,
              onTap: onPick,
            ),
          ),
        ),
      ],
    );
  }
}

/// A suggestion: tapping pops it 0.92 → 1 over 260 ms.
class _Chip extends StatefulWidget {
  const _Chip({required this.name, required this.active, required this.onTap});

  final String name;
  final bool active;
  final ValueChanged<String> onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_taps),
      tween: Tween(begin: _taps == 0 ? 1 : 0.92, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: onbPop,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _taps++);
          widget.onTap(widget.name);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: widget.active ? onbInk : onbLine,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '@${widget.name}',
            style: onbBody(13, onbInk, FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// The optional referral code, and the reward it unlocks: a 73 place under
/// the field is kept from the start, so nothing below it jumps.
class _ReferralBlock extends StatelessWidget {
  const _ReferralBlock({
    required this.controller,
    required this.state,
    required this.referrer,
    required this.message,
    required this.rewardKey,
    required this.onChanged,
  });

  final TextEditingController controller;
  final _CodeState state;
  final String? referrer;
  final String? message;
  final GlobalKey rewardKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final valid = state == _CodeState.valid;
    final border = switch (state) {
      _CodeState.valid => onbGreen,
      _CodeState.rejected when message != null => onbRed,
      _ => onbLine,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              Text('Kode referal', style: onbBody(13, onbInk, FontWeight.w800)),
              const SizedBox(width: 8),
              Text('opsional', style: onbHand(16, onbMuted)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Box(
          border: border,
          child: Row(
            children: [
              const Icon(LucideIcons.ticket, size: 20, color: onbMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    // Typed lower case becomes upper, as the server's codes
                    // are; only letters and digits, 8 at most.
                    TextInputFormatter.withFunction(
                      (_, value) =>
                          value.copyWith(text: value.text.toUpperCase()),
                    ),
                    FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  cursorColor: onbRed,
                  style: onbBody(
                    16,
                    onbInk,
                    FontWeight.w800,
                  ).copyWith(letterSpacing: 1.4),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'contoh: SATOS728',
                    hintStyle: onbBody(
                      16,
                      const Color(0xFFB3AA9C),
                      FontWeight.w600,
                    ).copyWith(letterSpacing: 0),
                  ),
                ),
              ),
              _Tick(on: valid),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 73),
          child: Align(
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              reverseDuration: const Duration(milliseconds: 180),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween(
                        begin: const Offset(0, -8 / 73),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: onbOut,
                          reverseCurve: Curves.easeIn,
                        ),
                      ),
                  child: child,
                ),
              ),
              child: valid
                  ? _Reward(key: rewardKey, referrer: referrer)
                  : message != null
                  ? _Hint(message!, onbRed)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Diajak @satoshi": what a valid code earns the friend, 73 tall. The
/// coupon pops in over 640 ms, 80 after the card: from 0.3 and −24° up to
/// 1.12 and 6°, then settling at 4° as the design has it.
class _Reward extends StatefulWidget {
  const _Reward({super.key, required this.referrer});

  final String? referrer;

  @override
  State<_Reward> createState() => _RewardState();
}

class _RewardState extends State<_Reward> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 73,
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E6),
        border: Border.all(color: const Color(0xFFF1D9B5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              // 80 ms in, 640 long, `pop`; the middle key (60%) overshoots.
              final t = onbTrack(
                _c.value * 720,
                80,
                640,
                const Cubic(.3, .7, .3, 1),
              );
              final over = t < 0.6 ? t / 0.6 : 1.0;
              final settle = t < 0.6 ? 0.0 : (t - 0.6) / 0.4;
              final scale = t < 0.6
                  ? 0.3 + (1.12 - 0.3) * over
                  : 1.12 + (1 - 1.12) * settle;
              final deg = t < 0.6
                  ? -24 + (6 - -24) * over
                  : 6 + (4 - 6) * settle;
              return Opacity(
                opacity: (t / 0.6).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: deg * math.pi / 180,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: Image.asset(
              'assets/images/referral/kupon-coretan.webp',
              width: 84,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Spill(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.referrer == null
                        ? 'Diajak teman 🎉'
                        : 'Diajak @${widget.referrer} 🎉',
                    style: onbBody(14, onbInk, FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kamu dapat kupon Gratis Ongkir begitu akunmu jadi.',
                    style: onbBody(12.5, onbMuted, FontWeight.w400, 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hand-drawn icon each intent carries.
String _intentDrawing(OnboardingIntent intent) => switch (intent) {
  OnboardingIntent.collect => 'icon_koleksi',
  OnboardingIntent.buy => 'icon_cari',
  OnboardingIntent.sell => 'icon_jual',
  OnboardingIntent.bid => 'icon_tawar',
};

/// One "Mau ngapain?" option, 80 tall. Ticked, it becomes a sticker: ink
/// outline, a hard 3,3 shadow and a nudge of 1 up and left, over 300 ms,
/// and its ring turns into a drawn tick.
class _Opt extends StatelessWidget {
  const _Opt({
    required this.intent,
    required this.selected,
    required this.onTap,
    required this.drawDelay,
    required this.animate,
  });

  final OnboardingIntent intent;
  final bool selected;
  final VoidCallback? onTap;
  final Duration drawDelay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: onbOut,
        height: 80,
        transform: Matrix4.translationValues(
          selected ? -1 : 0,
          selected ? -1 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? onbInk : onbLine,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected ? onbInk : Colors.transparent,
              offset: const Offset(3, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 52,
                    child: ScribbleDrawing(
                      drawing: _intentDrawing(intent),
                      stepMs: 40,
                      idle: false,
                      animate: animate,
                      delay: drawDelay,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Spill(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            intent.title,
                            style: onbBody(16, onbInk, FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            intent.description,
                            style: onbBody(13, onbMuted, FontWeight.w400, 1.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CoretanRadio(selected: selected, size: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
