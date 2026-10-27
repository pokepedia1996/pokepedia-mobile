import 'dart:async';
import 'dart:io';

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
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/utils/id_phone.dart';
import '../../../../shared/utils/image_crop.dart';
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

enum _Step { profile, phone, code, pickup, couriers, done }

/// Buka Toko: store profile (optional), phone, pickup point, couriers, and
/// the open store.
///
/// A phone already verified is not asked for again: the flow goes from the
/// profile straight to the pickup point, and back again past it.
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

  /// Which way the last move went, so the next step slides in from the
  /// side it lies on: ahead from the right, back from the left.
  bool _forward = true;

  void _go(_Step step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _forward = step.index > _step.index;
      _step = step;
    });
  }

  /// A short slide and fade between steps rather than a hard cut. The step
  /// leaving takes no taps while it goes, so a double tap on "Lanjut"
  /// can't land on the button underneath it.
  Widget _transition(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey(_step);
    final dx = (incoming ? 1 : -1) * (_forward ? 1 : -1) * 0.12;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return IgnorePointer(
      ignoring: !incoming,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: Offset(dx, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  void _back() {
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
      case _Step.done:
        _close();
    }
  }

  /// Leaving a finished store: the Jual tab, now its dashboard.
  void _close() => context.go(Routes.seller);

  /// Past the profile: the phone, unless it is already verified.
  void _afterProfile() => _go(_phoneVerified ? _Step.pickup : _Step.phone);

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return PopScope(
      canPop: _step == _Step.profile,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: _transition,
            // Full size, top aligned: each step is a whole screen, and the
            // default centred stack would jump while two of them overlap.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                _Step.profile => _ProfileStep(
                  draft: _draft,
                  palette: palette,
                  onBack: _back,
                  onNext: _afterProfile,
                ),
                _Step.phone => _PhoneStep(
                  palette: palette,
                  initial: _sentTo,
                  onBack: _back,
                  onSent: (phone) {
                    _sentTo = phone;
                    _go(_Step.code);
                  },
                ),
                _Step.code => _CodeStep(
                  palette: palette,
                  phone: _sentTo!,
                  onBack: _back,
                  onVerified: () {
                    _draft.phone = _sentTo;
                    _go(_Step.pickup);
                  },
                ),
                _Step.pickup => PickupStep(
                  draft: _draft,
                  palette: palette,
                  onBack: _back,
                  onNext: () => _go(_Step.couriers),
                ),
                _Step.couriers => CourierStep(
                  draft: _draft,
                  palette: palette,
                  onBack: _back,
                  onOpened: (warnings) {
                    _warnings = warnings;
                    _go(_Step.done);
                  },
                ),
                _Step.done => StoreReadyStep(
                  draft: _draft,
                  palette: palette,
                  warnings: _warnings,
                  onClose: _close,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- 1 · Profil toko

class _ProfileStep extends StatefulWidget {
  const _ProfileStep({
    required this.draft,
    required this.palette,
    required this.onBack,
    required this.onNext,
  });

  final StoreSetupDraft draft;
  final DesignPalette palette;
  final VoidCallback onBack;
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
    final palette = widget.palette;
    final draft = widget.draft;
    final nameError = _nameError;

    return SetupStepLayout(
      palette: palette,
      content: [
        SetupProgress(
          step: 0,
          total: 4,
          palette: palette,
          onBack: widget.onBack,
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: SetupPill(
            label: 'Opsional',
            background: palette.chip,
            foreground: palette.muted,
            border: palette.border,
          ),
        ),
        const SizedBox(height: 10),
        SetupHeadline(first: 'Kenalin', second: 'tokomu.', palette: palette),
        const SizedBox(height: 10),
        Text(
          'Boleh dilewati, default nama toko pakai username kamu.',
          style: setupText(15, palette.muted, FontWeight.w400, 22 / 15),
        ),
        const SizedBox(height: 24),
        _StorePreview(
          name: _name.text.trim().isEmpty ? draft.username : _name.text.trim(),
          draft: draft,
          palette: palette,
          onBanner: () => _pick(StorefrontImageKind.banner),
          onLogo: () => _pick(StorefrontImageKind.logo),
        ),
        const SizedBox(height: 24),
        Text('Nama toko', style: setupText(13, palette.ink, FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(
              color: nameError != null && _name.text.isNotEmpty
                  ? palette.error
                  : palette.border,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.store, size: 18, color: palette.muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  cursorColor: palette.brand,
                  style: setupText(16, palette.ink, FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: draft.username,
                    hintStyle: setupText(16, palette.muted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(LucideIcons.pencil, size: 16, color: palette.muted),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          nameError != null && _name.text.isNotEmpty
              ? nameError
              : 'Otomatis dari username. Bebas diganti, nggak harus sama.',
          style: setupText(
            12,
            nameError != null && _name.text.isNotEmpty
                ? palette.error
                : palette.muted,
          ),
        ),
      ],
      footer: [
        SetupPrimaryButton(
          label: 'Lanjut',
          palette: palette,
          onPressed: nameError == null ? _next : null,
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _skip,
            style: TextButton.styleFrom(foregroundColor: palette.muted),
            child: Text(
              'Nanti dulu',
              style: setupText(14, palette.muted, FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// How the store will look: the banner across the top, the photo over its
/// edge, the name, and "Aktif" — which it will be, once it opens.
class _StorePreview extends StatelessWidget {
  const _StorePreview({
    required this.name,
    required this.draft,
    required this.palette,
    required this.onBanner,
    required this.onLogo,
  });

  final String name;
  final StoreSetupDraft draft;
  final DesignPalette palette;
  final VoidCallback onBanner;
  final VoidCallback onLogo;

  @override
  Widget build(BuildContext context) {
    final banner = draft.banner;
    final logo = draft.logo;
    return Container(
      height: 236,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            height: 118,
            child: Material(
              color: palette.chip,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: banner == null
                    ? BorderSide(color: palette.brandBorder, width: 1.5)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBanner,
                child: banner != null
                    ? Image.memory(banner, fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.imagePlus,
                            size: 22,
                            color: palette.brand,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tambah banner',
                            style: setupText(14, palette.ink, FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Rasio 3:1 · JPG/PNG maks 4,5 MB',
                            style: setupText(12, palette.muted),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            top: 96,
            child: GestureDetector(
              onTap: onLogo,
              child: Container(
                width: 76,
                height: 76,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 4),
                ),
                child: logo != null
                    ? Image.memory(logo, fit: BoxFit.cover)
                    : Icon(LucideIcons.camera, size: 24, color: palette.brand),
              ),
            ),
          ),
          Positioned(
            left: 76,
            top: 148,
            child: IgnorePointer(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: palette.ctaBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 2),
                ),
                child: Icon(
                  logo == null ? LucideIcons.plus : LucideIcons.pencil,
                  size: 14,
                  color: palette.ctaForeground,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 192,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: setupText(16, palette.ink, FontWeight.w700),
                  ),
                ),
                SetupPill(
                  label: 'Aktif',
                  background: palette.successSoft,
                  foreground: palette.successText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- 2a · Nomor HP

class _PhoneStep extends ConsumerStatefulWidget {
  const _PhoneStep({
    required this.palette,
    required this.onBack,
    required this.onSent,
    this.initial,
  });

  final DesignPalette palette;
  final VoidCallback onBack;

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
    final palette = widget.palette;
    final typed = _number.text.isNotEmpty;

    return SetupStepLayout(
      palette: palette,
      top: 24,
      content: [
        SetupProgress(
          step: 1,
          total: 4,
          palette: palette,
          onBack: widget.onBack,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, setupSize(40), 0, setupSize(32)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetupHeadline(
                first: 'Nomor HP',
                second: 'kamu berapa?',
                palette: palette,
                size: 40,
                lineHeight: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'Untuk notifikasi pesanan & dihubungi kurir. Tidak '
                'ditampilkan ke publik.',
                style: setupText(16, palette.muted, FontWeight.w400, 22 / 16),
              ),
            ],
          ),
        ),
        Text('Nomor HP', style: setupText(14, palette.ink, FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: setupSize(64),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.brand, width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: palette.brand.withValues(alpha: 0.12),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              // Indonesian numbers only: that is all the server takes.
              Container(
                height: setupSize(48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const _IndonesianFlag(),
                    const SizedBox(width: 8),
                    Text(
                      '+62',
                      style: setupText(17, palette.ink, FontWeight.w700),
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
                    FontWeight.w600,
                  ).copyWith(letterSpacing: 0.5),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: '812 3456 7890',
                    hintStyle: setupText(
                      22,
                      palette.muted.withValues(alpha: 0.5),
                      FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (typed)
                IconButton(
                  onPressed: () => setState(() {
                    _number.clear();
                    _error = null;
                  }),
                  icon: Icon(
                    LucideIcons.circleX,
                    size: 18,
                    color: palette.muted,
                  ),
                  tooltip: 'Hapus',
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(_error!, style: setupText(13, palette.error, FontWeight.w500))
        else if (typed)
          Row(
            children: [
              Icon(
                _valid ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                size: 14,
                color: _valid ? palette.successText : palette.muted,
              ),
              const SizedBox(width: 6),
              Text(
                _valid
                    ? 'Format nomor sudah benar'
                    : 'Nomor HP diawali 8, 9–12 angka',
                style: setupText(
                  13,
                  _valid ? palette.successText : palette.muted,
                  FontWeight.w500,
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.successSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.messageCircle,
                  size: 18,
                  color: palette.successText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kode dikirim lewat WhatsApp',
                      style: setupText(14, palette.ink, FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pastikan nomor ini aktif di WhatsApp.',
                      style: setupText(13, palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      footer: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 13, color: palette.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Nomormu aman & hanya dipakai untuk transaksi.',
                style: setupText(12, palette.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SetupPrimaryButton(
          label: 'Kirim kode via WhatsApp',
          palette: palette,
          busy: _sending,
          onPressed: _valid && !_sending ? _send : null,
        ),
      ],
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
    // Indonesian flag everywhere. The file is a round flag, so it is drawn
    // round, with a hairline ring so the white half reads on a light chip.
    return Container(
      width: 22,
      height: 22,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: DesignPalette.of(context).border),
      ),
      decoration: const BoxDecoration(shape: BoxShape.circle),
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

class _CodeStep extends ConsumerStatefulWidget {
  const _CodeStep({
    required this.palette,
    required this.phone,
    required this.onBack,
    required this.onVerified,
  });

  final DesignPalette palette;
  final String phone;
  final VoidCallback onBack;
  final VoidCallback onVerified;

  @override
  ConsumerState<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<_CodeStep> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _ticker;
  late DateTime _resendAt;
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

  Future<void> _verify() async {
    if (_code.text.length != _codeLength || _verifying) return;
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
      if (mounted) widget.onVerified();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
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

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < _codeLength || !mounted) return;
    _code.text = digits.substring(0, _codeLength);
    setState(() => _error = null);
    _verify();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final wait = _wait;

    return SetupStepLayout(
      palette: palette,
      top: 24,
      content: [
        SetupProgress(
          step: 1,
          total: 4,
          palette: palette,
          onBack: widget.onBack,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, setupSize(40), 0, setupSize(32)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetupHeadline(
                first: 'Masukkan',
                second: 'kode 6 digit.',
                palette: palette,
                size: 40,
                lineHeight: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'Dikirim via WhatsApp ke',
                style: setupText(16, palette.muted),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  Text(
                    '+62 ${groupIdLocal(idPhoneLocalDigits(widget.phone))}',
                    style: setupText(16, palette.ink, FontWeight.w700),
                  ),
                  InkWell(
                    onTap: widget.onBack,
                    child: Text(
                      'Ubah',
                      style: setupText(16, palette.brand, FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _CodeBoxes(
          controller: _code,
          focusNode: _focus,
          palette: palette,
          error: _error != null,
          onChanged: (code) {
            setState(() => _error = null);
            if (code.length == _codeLength) _verify();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: setupText(13, palette.error, FontWeight.w500)),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 0),
          child: wait > Duration.zero
              ? Row(
                  children: [
                    Icon(LucideIcons.timer, size: 14, color: palette.muted),
                    const SizedBox(width: 6),
                    Text(
                      'Kirim ulang dalam ${wait.inMinutes}:'
                      '${(wait.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: setupText(14, palette.muted, FontWeight.w500),
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
                          size: 14,
                          color: palette.brand,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _resending ? 'Mengirim...' : 'Kirim ulang kode',
                          style: setupText(14, palette.brand, FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 28),
        Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _paste,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.clipboardPaste,
                      size: 16,
                      color: palette.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buka WhatsApp, salin kodenya, lalu tempel di sini.',
                      style: setupText(14, palette.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      footer: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Kode nggak masuk?', style: setupText(13, palette.muted)),
            TextButton(
              onPressed: () => context.push(Routes.support),
              style: TextButton.styleFrom(
                foregroundColor: palette.ink,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Hubungi CS',
                style: setupText(13, palette.ink, FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SetupPrimaryButton(
          label: 'Verifikasi',
          palette: palette,
          busy: _verifying,
          onPressed: _code.text.length == _codeLength && !_verifying
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
    required this.palette,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DesignPalette palette;
  final bool error;
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
                      child: _box(
                        digit: i < code.length ? code[i] : null,
                        current:
                            focusNode.hasFocus &&
                            i == code.length.clamp(0, _codeLength - 1),
                        filled: i < code.length,
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

  Widget _box({
    required String? digit,
    required bool current,
    required bool filled,
  }) {
    final border = error
        ? palette.error
        : current
        ? palette.brand
        : filled
        ? palette.brandBorder
        : palette.border;
    return Container(
      height: setupSize(64),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: border, width: current ? 1.5 : 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: current
            ? [
                BoxShadow(
                  color: palette.brand.withValues(alpha: 0.15),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: digit != null
          ? Text(digit, style: setupHeading(28, palette.ink))
          : current
          ? Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: palette.brand,
                borderRadius: BorderRadius.circular(1),
              ),
            )
          : null,
    );
  }
}
