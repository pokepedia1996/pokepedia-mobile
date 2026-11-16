import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/errors/user_message.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/utils/id_phone.dart';
import '../../../../shared/utils/image_crop.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/scribble_drawing.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../../account/usecase/address_notifier.dart';
import '../../../user/usecase/user_notifier.dart';
import '../../repository/models/store_profile.dart';
import '../../usecase/store_profile_notifier.dart';
import '../../usecase/store_setup.dart';
import 'courier_step.dart';
import 'pickup_step.dart';
import 'store_ready_step.dart';
import 'store_setup_parts.dart';

enum _Step { profile, phone, code, pickup, couriers, manualCouriers, done }

/// Buka Toko: store profile (optional), phone, pickup point, couriers —
/// recommended, or picked by hand — and the open store.
///
/// A phone already verified is not asked for again: the flow goes from the
/// profile straight to the pickup point, and back again past it.
///
/// Drawn on cream in the light theme whatever the app's: the designs have
/// no dark version, and the drawings are ink on paper.
class StoreSetupPage extends ConsumerStatefulWidget {
  const StoreSetupPage({super.key});

  @override
  ConsumerState<StoreSetupPage> createState() => _StoreSetupPageState();
}

class _StoreSetupPageState extends ConsumerState<StoreSetupPage> {
  late final StoreSetupDraft _draft;
  _Step _step = _Step.profile;

  /// The number the code went to, while step 2b waits for it.
  String? _sentTo;

  /// What opening the store left undone, for the last screen.
  List<String> _warnings = const [];

  /// The store is opening: back holds until it has, or hasn't.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    _draft = StoreSetupDraft(
      username: user?.username ?? user?.email.split('@').first ?? '',
    );
    final private = ref.read(privateProfileProvider).valueOrNull;
    if (private != null && private.phoneVerified) _draft.phone = private.phone;
    unawaited(_prefillPickup());
  }

  /// A pickup point saved from Alamat before the store existed. Step 1
  /// comes first, so this has landed by the time the map is shown.
  Future<void> _prefillPickup() async {
    try {
      final profile = await ref.read(storeProfileProvider.future);
      if (profile == null) return;
      final catalog = await ref.read(areaCatalogProvider.future);
      if (mounted) setState(() => _draft.prefillPickup(profile, catalog));
    } catch (_) {
      // Nothing to start from; the pickup step opens empty as before.
    }
  }

  bool get _phoneVerified => _draft.phone != null;

  /// Which way the last move went: ahead pushes the next screen in from
  /// the right, back slides the current one away to it.
  bool _forward = true;

  void _go(_Step step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _forward = step.index > _step.index;
      _step = step;
    });
  }

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _Step.profile:
        Navigator.of(context).maybePop();
      case _Step.phone:
        _go(_Step.profile);
      case _Step.code:
        _go(_Step.phone);
      case _Step.pickup:
        _go(_Step.profile);
      case _Step.couriers:
        _go(_Step.pickup);
      case _Step.manualCouriers:
        _go(_Step.couriers);
      case _Step.done:
        _close();
    }
  }

  /// Leaving a finished store: the Jual tab, now its dashboard.
  void _close() => context.go(Routes.seller);

  /// Past the profile: the phone, unless it is already verified.
  void _afterProfile() => _go(_phoneVerified ? _Step.pickup : _Step.phone);

  void _opened(List<String> warnings) {
    _warnings = warnings;
    _go(_Step.done);
  }

  /// The number the header reads for each step: the code is still the
  /// phone's step, and picking couriers by hand still the couriers'.
  int? get _headerStep => switch (_step) {
    _Step.profile => 1,
    _Step.phone || _Step.code => 2,
    _Step.pickup => 3,
    _Step.couriers || _Step.manualCouriers => 4,
    _Step.done => null,
  };

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
  }

  Widget _screen() => switch (_step) {
    _Step.profile => _ProfileStep(draft: _draft, onNext: _afterProfile),
    _Step.phone => _PhoneStep(
      initial: _sentTo,
      onSent: (phone) {
        _sentTo = phone;
        _go(_Step.code);
      },
    ),
    _Step.code => _CodeStep(
      phone: _sentTo!,
      onChangeNumber: _back,
      onVerified: () {
        _draft.phone = _sentTo;
        _go(_Step.pickup);
      },
    ),
    _Step.pickup => PickupStep(
      draft: _draft,
      onNext: () => _go(_Step.couriers),
    ),
    _Step.couriers => CourierStep(
      draft: _draft,
      onManual: () => _go(_Step.manualCouriers),
      onOpened: _opened,
      onBusy: _setBusy,
    ),
    _Step.manualCouriers => ManualCourierStep(
      draft: _draft,
      onOpened: _opened,
      onBusy: _setBusy,
    ),
    _Step.done => StoreReadyStep(
      draft: _draft,
      warnings: _warnings,
      onClose: _close,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: _step == _Step.profile,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            backgroundColor: AppColors.onbCream,
            // One page for the whole flow: the paper and the header stay,
            // and only what the step asks changes under them.
            body: CoretanBackground(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: coretanStepDuration,
                        transitionBuilder: (child, animation) =>
                            coretanStepTransition(
                              context: context,
                              child: child,
                              animation: animation,
                              incoming: child.key == ValueKey(_step),
                              forward: _forward,
                            ),
                        // Full size, top aligned: a step fills the space
                        // under the header, and the default centred stack
                        // would jump while two of them overlap.
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _screen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back, the four segments and "2/4" — the same header across every step,
  /// so its bar fills rather than being drawn again. The finished store has
  /// its own close button, and the header folds away for it.
  Widget _header() {
    final step = _headerStep;
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: coretanOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: step == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: const ValueKey('header'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: CoretanStepHeader(
                  step: step,
                  onBack: _busy ? null : _back,
                ),
              ),
      ),
    );
  }
}

// ------------------------------------------------------- 1 · Profil toko

class _ProfileStep extends StatefulWidget {
  const _ProfileStep({required this.draft, required this.onNext});

  final StoreSetupDraft draft;
  final VoidCallback onNext;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  late final _name = TextEditingController(text: widget.draft.storeName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _nameError {
    final length = _name.text.trim().length;
    if (length < 3) return 'Nama toko minimal 3 karakter.';
    if (length > 40) return 'Nama toko maksimal 40 karakter.';
    return null;
  }

  /// Cropped now to web's preset, so what the preview shows is what the
  /// store will show; uploaded only when the store opens.
  Future<void> _pick(StorefrontImageKind kind) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 3000,
    );
    if (picked == null || !mounted) return;
    final bytes = await File(picked.path).readAsBytes();
    final cropped = cropToAspect(
      bytes,
      targetWidth: kind.width,
      targetHeight: kind.height,
    );
    if (!mounted) return;
    if (cropped == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Gagal memproses foto, coba foto lain')),
        );
      return;
    }
    setState(() {
      if (kind == StorefrontImageKind.logo) {
        widget.draft.logo = cropped;
      } else {
        widget.draft.banner = cropped;
      }
    });
  }

  void _next() {
    final draft = widget.draft;
    draft.storeName = _name.text.trim();
    draft.profileSet =
        draft.storeName != draft.username ||
        draft.logo != null ||
        draft.banner != null;
    widget.onNext();
  }

  /// "Nanti dulu": the username for a name, no pictures.
  void _skip() {
    final draft = widget.draft
      ..storeName = widget.draft.username
      ..logo = null
      ..banner = null
      ..profileSet = false;
    _name.text = draft.username;
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final draft = widget.draft;
    final nameError = _nameError;
    final showError = nameError != null && _name.text.isNotEmpty;

    return SetupStepLayout(
      content: [
        const SetupIntro(
          eyebrow: 'langkah 1 dari 4 · opsional',
          first: 'Kenalin',
          second: 'tokomu.',
          sub: 'Boleh dilewati, default nama toko pakai username kamu.',
        ),
        _StorePreview(
          name: _name.text.trim().isEmpty ? draft.username : _name.text.trim(),
          draft: draft,
          onBanner: () => _pick(StorefrontImageKind.banner),
          onLogo: () => _pick(StorefrontImageKind.logo),
        ),
        const SizedBox(height: 22),
        Text('Nama toko', style: setupText(15, palette.ink, FontWeight.w700)),
        const SizedBox(height: 8),
        _PaperField(
          error: showError,
          child: Row(
            children: [
              Icon(LucideIcons.store, size: 19, color: palette.muted),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  cursorColor: palette.brand,
                  style: setupText(18, palette.ink, FontWeight.w700),
                  decoration: _bare(draft.username, palette),
                ),
              ),
              const SizedBox(width: 10),
              Icon(LucideIcons.pencil, size: 18, color: palette.muted),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CoretanHint(
          showError
              ? nameError
              : 'Otomatis dari username. Bebas diganti, nggak harus sama.',
          color: showError ? palette.error : palette.muted,
        ),
      ],
      footer: [
        CoretanButton(
          label: 'Lanjut',
          onPressed: nameError == null ? _next : null,
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _skip,
            style: TextButton.styleFrom(foregroundColor: palette.muted),
            child: Text(
              'Nanti dulu',
              style: setupText(16, palette.muted, FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// A text field with nothing of its own drawn: the paper around it is.
InputDecoration _bare(String hint, DesignPalette palette) => InputDecoration(
  isCollapsed: true,
  counterText: '',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  filled: false,
  hintText: hint,
  hintStyle: setupText(18, palette.muted, FontWeight.w600),
);

/// The white field the designs put on cream: 60 tall, rounded, a hairline
/// that turns [accent] — or red, for an [error] — as it changes.
class _PaperField extends StatelessWidget {
  const _PaperField({
    required this.child,
    this.error = false,
    this.accent,
    this.height = 60,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final bool error;
  final Color? accent;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final color = error ? palette.error : accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: setupSize(height),
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color ?? AppColors.onbLine,
          width: color == null ? 1.5 : 2,
        ),
      ),
      child: child,
    );
  }
}

/// How the store will look: the banner across the top, the photo over its
/// edge, the name, and "Aktif" — which it will be, once it opens.
class _StorePreview extends StatelessWidget {
  const _StorePreview({
    required this.name,
    required this.draft,
    required this.onBanner,
    required this.onLogo,
  });

  final String name;
  final StoreSetupDraft draft;
  final VoidCallback onBanner;
  final VoidCallback onLogo;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final banner = draft.banner;
    final logo = draft.logo;
    return CoretanCard(
      child: SizedBox(
        height: 232,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              height: 120,
              child: GestureDetector(
                onTap: onBanner,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: banner != null
                      ? Image.memory(banner, fit: BoxFit.cover)
                      : ColoredBox(
                          color: AppColors.codeBg,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ScribbleDrawing(
                                drawing: 'toko_bannerDash',
                                idle: false,
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.imagePlus,
                                    size: 22,
                                    color: palette.muted,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tambah banner',
                                    style: setupText(
                                      16,
                                      palette.ink,
                                      FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rasio 3:1 · JPG/PNG maks 4,5 MB',
                                    style: setupText(13, palette.muted),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 88,
              child: GestureDetector(
                onTap: onLogo,
                child: SizedBox.square(
                  dimension: 78,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: logo != null
                            ? Padding(
                                padding: const EdgeInsets.all(4),
                                child: ClipOval(
                                  child: Image.memory(logo, fit: BoxFit.cover),
                                ),
                              )
                            : const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: ScribbleDrawing(
                                    drawing: 'toko_kamera',
                                    size: 48,
                                    stepMs: 40,
                                    idle: false,
                                  ),
                                ),
                              ),
                      ),
                      const Positioned.fill(
                        child: ScribbleDrawing(
                          drawing: 'toko_avRing',
                          idle: false,
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -2,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: palette.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            logo == null
                                ? LucideIcons.plus
                                : LucideIcons.pencil,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 112,
              right: 16,
              top: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CoretanPop(
                            value: name,
                            from: 0.94,
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: setupHeading(21, palette.ink),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SetupPill(
                        label: 'Aktif',
                        background: palette.successSoft,
                        foreground: palette.successText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'pratinjau tokomu',
                    style: AppTypography.hand(palette.brand, size: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- 2a · Nomor HP

class _PhoneStep extends ConsumerStatefulWidget {
  const _PhoneStep({required this.onSent, this.initial});

  /// With the number as the server normalised it — the one to verify.
  final ValueChanged<String> onSent;

  /// The number from a code already sent, when coming back to change it.
  final String? initial;

  @override
  ConsumerState<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends ConsumerState<_PhoneStep> {
  late final _number = TextEditingController(
    text: widget.initial == null
        ? ''
        : groupIdLocal(idPhoneLocalDigits(widget.initial!)),
  );
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String get _local => idPhoneLocalDigits(_number.text);
  bool get _valid => isIdMobileLocal(_local);

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final normalised = await ref
          .read(phoneOtpRepositoryProvider)
          .send('+62$_local');
      if (!mounted) return;
      widget.onSent(normalised);
    } catch (e) {
      // The route's own words — a number taken by another account, a
      // cooldown — say more than anything restated here.
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final typed = _number.text.isNotEmpty;
    const green = Color(0xFF2E9E57);

    return SetupStepLayout(
      content: [
        const SetupIntro(
          eyebrow: 'langkah 2 dari 4',
          first: 'Nomor HP',
          second: 'kamu berapa?',
          sub:
              'Untuk notifikasi pesanan & dihubungi kurir. Tidak ditampilkan '
              'ke publik.',
        ),
        Text('Nomor HP', style: setupText(15, palette.ink, FontWeight.w700)),
        const SizedBox(height: 8),
        _PaperField(
          height: 68,
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
          error: _error != null || (typed && !_valid),
          accent: _valid ? green : null,
          child: Row(
            children: [
              // Indonesian numbers only: that is all the server takes. Drawn
              // as a coupon chip, like the codes in this style.
              Container(
                height: setupSize(52),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.codeBg,
                  border: Border.all(color: AppColors.codeLine),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const _IndonesianFlag(),
                    const SizedBox(width: 8),
                    Text(
                      '+62',
                      style: setupText(18, palette.ink, FontWeight.w800),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _number,
                  autofocus: widget.initial == null,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [_LocalPhoneFormatter()],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _send(),
                  cursorColor: palette.brand,
                  style: setupText(
                    22,
                    palette.ink,
                    FontWeight.w700,
                  ).copyWith(letterSpacing: 0.5),
                  decoration: _bare('812 3456 7890', palette).copyWith(
                    hintStyle: setupText(22, AppColors.onbOff, FontWeight.w700),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _valid
                    ? const ScribbleDrawing(
                        key: ValueKey('ok'),
                        drawing: 'icon_ok',
                        size: 28,
                        stepMs: 40,
                        idle: false,
                      )
                    : const SizedBox.square(dimension: 28),
              ),
            ],
          ),
        ),
        // Always here, empty or not, so the blocks below keep their place.
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 22),
          child: _error != null
              ? CoretanHint(_error!, color: palette.error)
              : typed
              ? CoretanHint(
                  _valid
                      ? 'Format nomor sudah benar'
                      : 'Diawali 8, 9–12 angka (tanpa 0 di depan)',
                  color: _valid ? green : palette.error,
                )
              : const SizedBox.shrink(),
        ),
        _NoteCard(
          drawing: 'toko_chat',
          background: const Color(0xFFEEF6EF),
          border: const Color(0xFFD3E9D8),
          title: 'Kode dikirim lewat WhatsApp',
          body: 'Pastikan nomor ini aktif di WhatsApp.',
        ),
      ],
      footer: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 14, color: palette.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Nomormu aman & hanya dipakai untuk transaksi.',
                style: setupText(14, palette.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CoretanButton(
          label: 'Kirim kode via WhatsApp',
          busy: _sending,
          onPressed: _valid ? _send : null,
        ),
      ],
    );
  }
}

/// A tinted card with a drawn icon: what happens next, said once.
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.drawing,
    required this.background,
    required this.border,
    required this.title,
    this.body,
    this.onTap,
  });

  final String drawing;
  final Color background;
  final Color border;
  final String title;
  final String? body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return CoretanCard(
      color: background,
      borderColor: border,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        children: [
          ScribbleDrawing(
            drawing: drawing,
            size: 46,
            stepMs: 40,
            delay: const Duration(milliseconds: 400),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: setupText(
                    16,
                    palette.ink,
                    body == null ? FontWeight.w500 : FontWeight.w800,
                    1.35,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(body!, style: setupText(15, palette.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the field to the digits after +62, grouped "812 3456 7890" as they
/// are typed — and takes a pasted "0812…" or "+62 812…" as the same number.
class _LocalPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = idPhoneLocalDigits(newValue.text);
    if (digits.length > 12) digits = digits.substring(0, 12);
    final grouped = groupIdLocal(digits);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}

/// Merah putih, drawn rather than an emoji, which renders differently on
/// every phone.
class _IndonesianFlag extends StatelessWidget {
  const _IndonesianFlag();

  @override
  Widget build(BuildContext context) {
    // The flag artwork the card-language badge uses, so the app shows one
    // Indonesian flag everywhere; here as the designs' little rectangle,
    // with a hairline so the white half reads on the cream chip.
    return Container(
      width: 26,
      height: 18,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.onbLine),
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
      child: SvgPicture.asset(
        'assets/images/flags/id.svg',
        fit: BoxFit.cover,
        semanticsLabel: 'Indonesia',
      ),
    );
  }
}

// ------------------------------------------------------- 2b · Kode OTP

/// The server's cooldown between codes (`OTP_COOLDOWN_MS`).
const _resendAfter = Duration(seconds: 60);
const _codeLength = 6;

/// A full code is checked after this pause, so the last digit is seen
/// landing before anything happens.
const _verifyPause = Duration(milliseconds: 350);

class _CodeStep extends ConsumerStatefulWidget {
  const _CodeStep({
    required this.phone,
    required this.onChangeNumber,
    required this.onVerified,
  });

  final String phone;

  /// "Ubah": back to the number.
  final VoidCallback onChangeNumber;
  final VoidCallback onVerified;

  @override
  ConsumerState<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<_CodeStep>
    with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  Timer? _ticker;
  Timer? _pending;
  late DateTime _resendAt;
  bool _verifying = false;
  bool _verified = false;
  bool _resending = false;
  bool _pasting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pending?.cancel();
    _shake.dispose();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _resendAt = DateTime.now().add(_resendAfter);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});
      if (!DateTime.now().isBefore(_resendAt)) timer.cancel();
    });
  }

  Duration get _wait {
    final left = _resendAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _onChanged(String code) {
    setState(() => _error = null);
    _pending?.cancel();
    if (code.length == _codeLength) {
      _pending = Timer(_verifyPause, _verify);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != _codeLength || _verifying || _verified) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref
          .read(phoneOtpRepositoryProvider)
          .verify(phone: widget.phone, code: _code.text);
      // Verified for the whole account: Settings, checkout and bids all
      // read it from here.
      ref.invalidate(privateProfileProvider);
      if (!mounted) return;
      // The boxes turn green and hop, and the step moves on after.
      setState(() => _verified = true);
      _focus.unfocus();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Nomor HP terverifikasi'),
            persist: false,
          ),
        );
      await Future<void>.delayed(
        coretanReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 650),
      );
      if (mounted) widget.onVerified();
    } catch (e) {
      if (!mounted) return;
      // The server's words — wrong, or expired — and the boxes shake and
      // empty for another go.
      setState(() => _error = userFacingError(e));
      await _shake.forward(from: 0);
      if (!mounted) return;
      _code.clear();
      _focus.requestFocus();
      setState(() {});
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(phoneOtpRepositoryProvider).send(widget.phone);
      if (!mounted) return;
      _code.clear();
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// "Buka WhatsApp, salin kodenya, lalu tempel di sini": the code from the
  /// clipboard, set down a digit at a time, then checked like a typed one.
  Future<void> _paste() async {
    if (_pasting || _verified) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < _codeLength || !mounted) return;
    final code = digits.substring(0, _codeLength);
    _pasting = true;
    final step = coretanReduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 90);
    for (var i = 1; i <= _codeLength; i++) {
      if (!mounted) return;
      _code.text = code.substring(0, i);
      setState(() => _error = null);
      if (i < _codeLength) await Future<void>.delayed(step);
    }
    _pasting = false;
    _onChanged(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final wait = _wait;

    return SetupStepLayout(
      content: [
        SetupIntro(
          eyebrow: 'langkah 2 dari 4',
          first: 'Masukkan',
          second: 'kode 6 digit.',
          subWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dikirim via WhatsApp ke',
                style: setupText(18, palette.muted),
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    '+62 ${groupIdLocal(idPhoneLocalDigits(widget.phone))}',
                    style: setupText(18, palette.ink, FontWeight.w800),
                  ),
                  InkWell(
                    onTap: widget.onChangeNumber,
                    child: Text(
                      'Ubah',
                      style: setupText(18, palette.brand, FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            // Three quick swings that die away.
            offset: Offset(
              10 *
                  math.sin(_shake.value * 3 * 2 * math.pi) *
                  (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: _CodeBoxes(
            controller: _code,
            focusNode: _focus,
            error: _error != null,
            verified: _verified,
            onChanged: _onChanged,
          ),
        ),
        // Always here, empty or not, so the blocks below keep their place.
        _error != null
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: CoretanHint(_error!, color: palette.error),
              )
            : const SizedBox.shrink(),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
          child: wait > Duration.zero
              ? Row(
                  children: [
                    Icon(LucideIcons.timer, size: 16, color: palette.muted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Kirim ulang dalam ${wait.inMinutes}:'
                        '${(wait.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: AppTypography.hand(palette.muted, size: 19),
                      ),
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: _resending ? null : _resend,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.rotateCw,
                          size: 16,
                          color: palette.brand,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _resending ? 'Mengirim...' : 'Kirim ulang kode',
                            style: AppTypography.hand(palette.brand, size: 19),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 22),
        _NoteCard(
          drawing: 'toko_salin',
          background: AppColors.codeBg,
          border: AppColors.codeLine,
          title: 'Buka WhatsApp, salin kodenya, lalu tempel di sini.',
          onTap: _paste,
        ),
      ],
      footer: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Kode nggak masuk?', style: setupText(15, palette.muted)),
            TextButton(
              onPressed: () => context.push(Routes.support),
              style: TextButton.styleFrom(
                foregroundColor: palette.brand,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Hubungi CS',
                style: setupText(15, palette.brand, FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CoretanButton(
          label: 'Verifikasi',
          busy: _verifying,
          onPressed: _code.text.length == _codeLength && !_verified
              ? _verify
              : null,
        ),
      ],
    );
  }
}

/// Six boxes over one hidden field: a box per digit for the eye, one field
/// for the keyboard — which is what lets the OS offer the code from the
/// message, and a paste land whole.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.verified,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool error;
  final bool verified;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Under the boxes and invisible, but the thing that has focus.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              readOnly: verified,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: _codeLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: focusNode.requestFocus,
          child: ListenableBuilder(
            listenable: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final code = controller.text;
              return Row(
                children: [
                  for (var i = 0; i < _codeLength; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _CodeBox(
                        index: i,
                        digit: i < code.length ? code[i] : null,
                        current:
                            !verified &&
                            focusNode.hasFocus &&
                            i == code.length.clamp(0, _codeLength - 1),
                        error: error,
                        verified: verified,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One digit's box: empty, waiting with a blinking red caret, filled in
/// ink with a hard shadow — and green with a little hop once the code is
/// right.
class _CodeBox extends StatefulWidget {
  const _CodeBox({
    required this.index,
    required this.digit,
    required this.current,
    required this.error,
    required this.verified,
  });

  final int index;
  final String? digit;
  final bool current;
  final bool error;
  final bool verified;

  @override
  State<_CodeBox> createState() => _CodeBoxState();
}

class _CodeBoxState extends State<_CodeBox> with TickerProviderStateMixin {
  // Made in initState, not lazily: a box that never gets a digit never
  // touches [_pop], and a controller first made in dispose() fails.
  late final AnimationController _blink;
  late final AnimationController _pop;
  late final AnimationController _hop;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  bool get _still => coretanReduceMotion(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_CodeBox old) {
    super.didUpdateWidget(old);
    _syncBlink();
    if (widget.digit != null && old.digit == null && !_still) {
      _pop.forward(from: 0);
    }
    if (widget.verified && !old.verified && !_still) {
      Future<void>.delayed(Duration(milliseconds: 45 * widget.index), () {
        if (mounted) _hop.forward(from: 0);
      });
    }
  }

  /// A caret only blinks while it is the one waiting — and not at all with
  /// reduced motion, where it simply shows.
  void _syncBlink() {
    if (widget.current && !_still) {
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    _pop.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    const green = Color(0xFF2E9E57);
    final filled = widget.digit != null;
    final Color border;
    final double width;
    if (widget.verified) {
      (border, width) = (green, 2);
    } else if (widget.error) {
      (border, width) = (palette.error, 2.2);
    } else if (widget.current) {
      (border, width) = (palette.brand, 2.2);
    } else if (filled) {
      (border, width) = (palette.ink, 2);
    } else {
      (border, width) = (AppColors.onbLine, 1.5);
    }

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: setupSize(68),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.verified ? const Color(0xFFE6F4EA) : palette.surface,
        border: Border.all(color: border, width: width),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: filled && !widget.error
                ? (widget.verified ? green : palette.ink)
                : Colors.transparent,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: filled
          ? ScaleTransition(
              scale: TweenSequence([
                TweenSequenceItem(
                  tween: Tween(begin: .7, end: 1.08),
                  weight: 60,
                ),
                TweenSequenceItem(
                  tween: Tween(begin: 1.08, end: 1.0),
                  weight: 40,
                ),
              ]).animate(_pop),
              child: Text(
                widget.digit!,
                style: setupHeading(30, widget.verified ? green : palette.ink),
              ),
            )
          : widget.current
          ? FadeTransition(
              // On for the first half of each second, off for the second.
              opacity: _blink.drive(
                TweenSequence([
                  TweenSequenceItem(tween: ConstantTween(1.0), weight: 1),
                  TweenSequenceItem(tween: ConstantTween(0.0), weight: 1),
                ]),
              ),
              child: Container(
                width: 2.4,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.brand,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            )
          : null,
    );

    return AnimatedBuilder(
      animation: _hop,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -8 * math.sin(_hop.value * math.pi)),
        child: child,
      ),
      child: box,
    );
  }
}
