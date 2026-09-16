import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../user/usecase/user_notifier.dart';

/// `profiles.username`'s own format rule, mirrored from
/// `components/auth/onboarding-modal.tsx`. The unique index still has the
/// final say — this only spares an obviously-bad name a round trip.
final _usernameFormat = RegExp(r'^[a-zA-Z0-9_]{3,15}$');

const _totalSteps = 4;

/// How long to sit on a keystroke before asking the server, as on the web.
const _checkDebounce = Duration(milliseconds: 400);

/// What the availability check currently says about the typed name.
///
/// [unverifiable] is deliberately distinct from [taken]: the RPC failing is
/// not an answer, and this modal cannot be dismissed — treating "could not
/// ask" as "no" would lock someone out of the whole app behind a name they
/// are not allowed to keep and cannot replace.
enum _NameState { idle, checking, available, taken, unverifiable }

typedef _TutorialStep = ({IconData icon, String title, String description});

const _tutorialSteps = <_TutorialStep>[
  (
    icon: LucideIcons.sparkles,
    title: 'Selamat Datang!',
    description:
        'Selamat datang di database kartu Pokémon Indonesia terlengkap. '
        'Kamu bisa cari kartu, catat inventori, dan bagikan koleksi ke teman.',
  ),
  (
    icon: LucideIcons.search,
    title: 'Jelajahi Ekspansi',
    description:
        'Pilih set yang mau kamu eksplor, dan tambahkan kartu ke portofoliomu.',
  ),
  (
    icon: LucideIcons.folderOpen,
    title: 'Kelola Koleksimu',
    description:
        'Sync koleksimu, lengkapi data, simpan semua, cek aktivitas, dan '
        'hapus kartu dari inventori.',
  ),
];

/// Shows [OnboardingModal] over whatever is on screen once the signed-in
/// user turns out not to have finished onboarding. Ports the way web mounts
/// the modal in its root layout rather than on one route: a social sign-in
/// can land on any screen, and the username is owed either way.
///
/// Mounted from `MaterialApp.router`'s builder, so it covers pushed routes
/// and shell tabs alike.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    // Only an explicit false opens it: null means the profile row hasn't
    // landed yet, and guessing would flash the modal over every launch.
    final show = user != null && user.onboarded == false;

    return Stack(
      children: [
        child,
        // The modal carries its own Overlay. `MaterialApp.builder` runs
        // *above* the router's Navigator, so this subtree sits outside the
        // app's Overlay — and a TextField needs one in scope to place its
        // selection handles and toolbar. Without it, tapping the username
        // field throws "No Overlay widget found" instead of focusing.
        if (show)
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(builder: (_) => const OnboardingModal()),
              ],
            ),
          ),
      ],
    );
  }
}

/// A first-run tutorial ending in the username the account has never had.
///
/// Ports `components/auth/onboarding-modal.tsx`. `handle_new_user` writes
/// every profile with a null username, and neither the signup form nor a
/// Google/Apple sign-in asks for one — so without this the account keeps
/// falling back to the email local-part and has no profile to link to.
class OnboardingModal extends ConsumerStatefulWidget {
  const OnboardingModal({super.key});

  @override
  ConsumerState<OnboardingModal> createState() => _OnboardingModalState();
}

class _OnboardingModalState extends ConsumerState<OnboardingModal> {
  final _controller = TextEditingController();

  int _step = 0;
  Timer? _debounce;
  _NameState _nameState = _NameState.idle;
  bool _submitting = false;
  String? _error;
  bool _prefilled = false;

  bool get _isUsernameStep => _step == _totalSteps - 1;

  /// A name may be submitted once it is well-formed and the server has not
  /// said no. [_NameState.unverifiable] counts: the check could not be made,
  /// and `completeOnboarding` already turns the unique-index violation into
  /// "Username sudah dipakai" if the name really is gone.
  bool get _canSubmit =>
      !_submitting &&
      _usernameFormat.hasMatch(_controller.text.trim()) &&
      (_nameState == _NameState.available ||
          _nameState == _NameState.unverifiable);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Google and Apple hand back a display name; if it happens to be a legal
  /// username, offer it rather than making the user invent one.
  ///
  /// Guarded end to end: this is a convenience on top of a step the user can
  /// complete by typing, so nothing it touches is allowed to throw into the
  /// transition that opened the step.
  void _prefillFromMetadata() {
    if (_prefilled) return;
    _prefilled = true;
    try {
      final metadata = ref
          .read(supabaseClientProvider)
          .auth
          .currentUser
          ?.userMetadata;
      final suggested = (metadata?['display_name'] as String?)?.trim();
      if (suggested == null || !_usernameFormat.hasMatch(suggested)) return;
      _controller.text = suggested;
      _onUsernameChanged(suggested);
    } catch (_) {
      // No suggestion, which is exactly what an empty field already says.
    }
  }

  void _onUsernameChanged(String raw) {
    final value = raw.trim();
    _debounce?.cancel();
    setState(() {
      _error = null;
      _nameState = _NameState.idle;
    });
    if (value.isEmpty) return;

    if (!_usernameFormat.hasMatch(value)) {
      setState(
        () => _error = '3–15 karakter, hanya huruf, angka, dan underscore',
      );
      return;
    }

    setState(() => _nameState = _NameState.checking);
    _debounce = Timer(_checkDebounce, () => _check(value));
  }

  Future<void> _check(String value) async {
    final available = await ref
        .read(userRepositoryProvider)
        .isUsernameAvailable(value);
    if (!mounted) return;
    // A later keystroke moved on while this was in flight; the check it
    // scheduled owns the state now.
    if (_controller.text.trim() != value) return;

    setState(() {
      if (available == null) {
        // Not an answer. Let them through and let the unique index decide,
        // rather than trapping them in a modal with no way out.
        _nameState = _NameState.unverifiable;
        _error = 'Tidak bisa memeriksa ketersediaan. Kamu tetap bisa lanjut.';
      } else if (available) {
        _nameState = _NameState.available;
        _error = null;
      } else {
        _nameState = _NameState.taken;
        _error = 'Username sudah dipakai';
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await ref
        .read(authProvider.notifier)
        .completeOnboarding(_controller.text.trim());
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
        if (error == 'Username sudah dipakai') _nameState = _NameState.taken;
      });
      return;
    }
    // On success the profile reloads with `onboarded: true`, and the gate
    // above takes this modal down — nothing to do here.
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canSubmit = _canSubmit;

    // There is no way past this but to choose a name, as on the web, so the
    // back gesture must not dismiss it.
    return PopScope(
      canPop: false,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Material(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StepDots(current: _step),
                        const SizedBox(height: 20),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _isUsernameStep
                              ? _usernameStep(colors, canSubmit)
                              : _tutorialStep(colors),
                        ),
                        if (!_isUsernameStep) ...[
                          const SizedBox(height: 24),
                          _NavRow(
                            showBack: _step > 0,
                            onBack: () => setState(() => _step--),
                            onNext: () {
                              setState(() => _step++);
                              if (_isUsernameStep) _prefillFromMetadata();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tutorialStep(ColorScheme colors) {
    final step = _tutorialSteps[_step];
    return Column(
      key: ValueKey(_step),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(step.icon, size: 28, color: colors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: AppTypography.h3(colors.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          step.description,
          textAlign: TextAlign.center,
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ],
    );
  }

  Widget _usernameStep(ColorScheme colors, bool canSubmit) {
    return Column(
      key: const ValueKey('username'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pilih Username', style: AppTypography.h3(colors.onSurface)),
        const SizedBox(height: 6),
        Text(
          'Buat username unik untuk akunmu.',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 15,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: _onUsernameChanged,
          onSubmitted: (_) {
            if (canSubmit) _submit();
          },
          decoration: InputDecoration(
            labelText: 'Username',
            hintText: 'username_kamu',
            errorText: _error,
            counterText: '',
            prefixIcon: const Icon(LucideIcons.user, size: 18),
            suffixIcon: switch (_nameState) {
              _NameState.checking => const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              _NameState.available => Icon(
                LucideIcons.check,
                size: 18,
                color: colors.primary,
              ),
              _ => null,
            },
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mulai Jelajahi'),
        ),
      ],
    );
  }
}

/// The progress rail: the current step is a wide pill, the ones behind it are
/// filled dots, the ones ahead are faint.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _totalSteps; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: i == current ? 24 : 6,
            decoration: BoxDecoration(
              color: i == current
                  ? colors.primary
                  : i < current
                  ? colors.primary.withValues(alpha: 0.4)
                  : context.mutedForeground.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.showBack,
    required this.onBack,
    required this.onNext,
  });

  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Kept in the layout when hidden so "Lanjut" doesn't shift sideways
        // between the first step and the rest.
        Visibility(
          visible: showBack,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            label: const Text('Kembali'),
          ),
        ),
        TextButton.icon(
          onPressed: onNext,
          iconAlignment: IconAlignment.end,
          icon: const Icon(LucideIcons.chevronRight, size: 16),
          label: const Text('Lanjut'),
        ),
      ],
    );
  }
}
