import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../user/repository/models/profile_models.dart';
import '../../user/usecase/user_notifier.dart';

/// Handles accepted by web's `handleSaveSocial` — plain usernames only.
final _handleRe = RegExp(r'^[a-zA-Z0-9_.]{0,30}$');

/// Ports the "profil" tab of `app/settings/page.tsx` — profile photo,
/// username, phone verification state, password, collection privacy, bio
/// and social links, wired to the same Supabase tables and RPCs.
///
/// Two web sections have no mobile equivalent yet and render read-only:
/// the avatar upload (the app bundles no image picker) and phone OTP
/// (`/api/otp/*` are Next route handlers, not Supabase endpoints).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _whatsapp = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _tiktok = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _x = TextEditingController();

  bool _seeded = false;
  Timer? _usernameDebounce;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String? _usernameError;
  bool _savingUsername = false;
  bool _savingBio = false;
  bool _savingSocial = false;
  bool _savingPassword = false;
  bool _savingVisibility = false;
  bool _savingQuantity = false;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    for (final controller in [
      _username,
      _bio,
      _whatsapp,
      _facebook,
      _instagram,
      _tiktok,
      _x,
      _currentPassword,
      _newPassword,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seed(PublicProfile profile, PrivateProfile private) {
    if (_seeded) return;
    _seeded = true;
    _username.text = profile.username;
    _bio.text = profile.bio ?? '';
    _facebook.text = profile.socialFacebook ?? '';
    _instagram.text = profile.socialInstagram ?? '';
    _tiktok.text = profile.socialTiktok ?? '';
    _x.text = profile.socialX ?? '';
    _whatsapp.text = private.socialWhatsapp ?? '';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Username -----------------------------------------------------------

  void _onUsernameChanged(String value, String current) {
    setState(() {
      _usernameError = null;
      _usernameAvailable = null;
    });
    _usernameDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == current) return;
    if (trimmed.length < 3) {
      setState(() => _usernameError = 'Username minimal 3 karakter');
      return;
    }
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _checkingUsername = true);
      final available = await ref
          .read(userRepositoryProvider)
          .isUsernameAvailable(trimmed);
      if (!mounted) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = available;
        _usernameError = available == null
            ? 'Gagal memeriksa username'
            : (available ? null : 'Username sudah dipakai');
      });
    });
  }

  Future<void> _saveUsername(String userId) async {
    setState(() => _savingUsername = true);
    final error = await ref.read(userRepositoryProvider).updateProfile(userId, {
      'username': _username.text.trim(),
    });
    if (!mounted) return;
    setState(() => _savingUsername = false);
    if (error != null) {
      _toast('Gagal menyimpan username');
      return;
    }
    ref.invalidate(authProvider);
    ref.invalidate(myProfileProvider);
    _toast('Username disimpan');
  }

  // --- Bio & socials ------------------------------------------------------

  Future<void> _saveBio(String userId) async {
    setState(() => _savingBio = true);
    final value = _bio.text.trim();
    final error = await ref.read(userRepositoryProvider).updateProfile(userId, {
      'bio': value.isEmpty ? null : value,
    });
    if (!mounted) return;
    setState(() => _savingBio = false);
    ref.invalidate(myProfileProvider);
    _toast(
      error == null ? 'Deskripsi profil disimpan' : 'Gagal menyimpan deskripsi',
    );
  }

  Future<void> _saveSocial(String userId) async {
    final whatsapp = _whatsapp.text.replaceAll(RegExp(r'\D'), '');
    final facebook = _facebook.text.trim();
    final instagram = _instagram.text.trim().replaceFirst(RegExp(r'^@'), '');
    final tiktok = _tiktok.text.trim().replaceFirst(RegExp(r'^@'), '');
    final x = _x.text.trim().replaceFirst(RegExp(r'^@'), '');

    if (whatsapp.length > 15) {
      _toast('Nomor WhatsApp tidak valid');
      return;
    }
    for (final (label, value) in [
      ('Facebook', facebook),
      ('Instagram', instagram),
      ('TikTok', tiktok),
      ('X', x),
    ]) {
      if (!_handleRe.hasMatch(value)) {
        _toast('Username $label tidak valid');
        return;
      }
    }

    setState(() => _savingSocial = true);
    final repository = ref.read(userRepositoryProvider);
    final results = await Future.wait([
      repository.updateProfile(userId, {
        'social_facebook': facebook.isEmpty ? null : facebook,
        'social_instagram': instagram.isEmpty ? null : instagram,
        'social_tiktok': tiktok.isEmpty ? null : tiktok,
        'social_x': x.isEmpty ? null : x,
      }),
      repository.updateWhatsapp(whatsapp),
    ]);
    if (!mounted) return;
    setState(() => _savingSocial = false);
    ref.invalidate(myProfileProvider);
    ref.invalidate(privateProfileProvider);
    _toast(
      results.every((e) => e == null)
          ? 'Media sosial disimpan'
          : 'Gagal menyimpan media sosial',
    );
  }

  // --- Password -----------------------------------------------------------

  Future<void> _savePassword(String email) async {
    final current = _currentPassword.text;
    final next = _newPassword.text;
    final confirm = _confirmPassword.text;

    setState(() {
      _currentPasswordError = current.isEmpty
          ? 'Password saat ini tidak boleh kosong'
          : null;
      _newPasswordError = next.isEmpty
          ? 'Password tidak boleh kosong'
          : (next.length < 8 ? 'Password minimal 8 karakter' : null);
      _confirmPasswordError = confirm.isEmpty
          ? 'Konfirmasi password tidak boleh kosong'
          : (next != confirm ? 'Password tidak cocok' : null);
    });
    if (_currentPasswordError != null ||
        _newPasswordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    setState(() => _savingPassword = true);
    final client = ref.read(supabaseClientProvider);
    try {
      // Web re-authenticates before changing the password so a hijacked
      // session can't lock the owner out; same guard here.
      await client.auth.signInWithPassword(email: email, password: current);
    } on AuthException {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
        _currentPasswordError = 'Password saat ini salah';
      });
      return;
    }

    final error = await ref.read(authProvider.notifier).updatePassword(next);
    if (!mounted) return;
    setState(() => _savingPassword = false);
    if (error != null) {
      _toast(_translatePasswordError(error));
      return;
    }
    _currentPassword.clear();
    _newPassword.clear();
    _confirmPassword.clear();
    _toast('Password berhasil diubah');
  }

  String _translatePasswordError(String message) {
    if (message.contains('should be different')) {
      return 'Password baru harus berbeda dari password lama';
    }
    if (message.contains('at least')) return 'Password minimal 8 karakter';
    return 'Gagal mengubah password';
  }

  // --- Privacy toggles ----------------------------------------------------

  Future<void> _toggleFlag({
    required String userId,
    required String column,
    required bool value,
    required String onLabel,
    required String offLabel,
    required void Function(bool) setSaving,
  }) async {
    setState(() => setSaving(true));
    final error = await ref
        .read(userRepositoryProvider)
        .updateCollectionVisibility(userId, {column: value});
    if (!mounted) return;
    setState(() => setSaving(false));
    if (error != null) {
      _toast('Gagal menyimpan pengaturan');
      return;
    }
    ref.invalidate(myCollectionVisibilityProvider);
    _toast(value ? onLabel : offLabel);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final profileAsync = ref.watch(myProfileProvider);
    final privateAsync = ref.watch(privateProfileProvider);
    final visibilityAsync = ref.watch(myCollectionVisibilityProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: user == null
            ? const Center(child: Text('Masuk untuk mengatur akun'))
            : profileAsync.isLoading || privateAsync.isLoading
            ? const PikachuLoader()
            : Builder(
                builder: (context) {
                  final profile = profileAsync.valueOrNull;
                  final private =
                      privateAsync.valueOrNull ?? const PrivateProfile();
                  if (profile != null) _seed(profile, private);

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text(
                        'Pengaturan',
                        style: AppTypography.h2(context.appColors.onSurface),
                      ),
                      const SizedBox(height: 16),
                      _IdentityCard(
                        // Web's own fallback: someone who has not chosen a
                        // username yet is shown by their email's local part.
                        name: (profile?.username ?? '').isNotEmpty
                            ? profile!.username
                            : user.email.split('@').first,
                        email: user.email,
                        avatarUrl: profile?.avatarUrl,
                      ),
                      const SizedBox(height: 12),
                      // Profil is where this page already is, so it reads as
                      // the current tab rather than a link.
                      const _NavItem(
                        icon: LucideIcons.userCog,
                        label: 'Profil',
                        active: true,
                      ),
                      const SizedBox(height: 4),
                      _NavItem(
                        icon: LucideIcons.mapPin,
                        label: 'Alamat',
                        onTap: () => context.push(Routes.addresses),
                      ),
                      const SizedBox(height: 12),
                      const _LegalLinks(),
                      const SizedBox(height: 20),
                      _PhotoSection(user: user),
                      const SizedBox(height: 16),
                      _usernameSection(user.id, profile?.username ?? ''),
                      const SizedBox(height: 16),
                      _phoneSection(private),
                      const SizedBox(height: 16),
                      _passwordSection(user.email),
                      const SizedBox(height: 16),
                      _privacySections(
                        user.id,
                        visibilityAsync.valueOrNull,
                      ),
                      const SizedBox(height: 16),
                      _bioSection(user.id),
                      const SizedBox(height: 16),
                      _socialSection(user.id),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _usernameSection(String userId, String currentUsername) {
    final trimmed = _username.text.trim();
    final canSave =
        !_savingUsername &&
        trimmed.isNotEmpty &&
        trimmed != currentUsername &&
        _usernameAvailable == true;

    return SettingsSection(
      title: 'Ubah Username',
      description: 'Berikan username unik pada akun kamu.',
      children: [
        TextField(
          controller: _username,
          maxLength: 15,
          onChanged: (value) => _onUsernameChanged(value, currentUsername),
          decoration: InputDecoration(
            hintText: 'username_kamu',
            prefixIcon: const Icon(LucideIcons.user, size: 20),
            counterText: '',
            errorText: _usernameError,
            suffixIcon: _checkingUsername
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _usernameAvailable == true
                ? Icon(
                    LucideIcons.check,
                    color: context.appColors.primary,
                    size: 20,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        _SaveButton(
          label: 'Simpan',
          loading: _savingUsername,
          onPressed: canSave ? () => _saveUsername(userId) : null,
        ),
      ],
    );
  }

  Widget _phoneSection(PrivateProfile private) {
    final colors = context.appColors;
    return SettingsSection(
      title: 'Verifikasi Nomor HP',
      description: 'Wajib untuk melakukan transaksi.',
      children: [
        Row(
          children: [
            Icon(
              private.phoneVerified
                  ? LucideIcons.badgeCheck
                  : LucideIcons.circleAlert,
              size: 18,
              color: private.phoneVerified
                  ? context.appSemantic.success
                  : context.mutedForeground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                private.phoneVerified
                    ? '${private.phone ?? 'Nomor'} · Terverifikasi'
                    : 'Belum terverifikasi',
                style: AppTypography.bodySm(colors.onSurface),
              ),
            ),
          ],
        ),
        // A verified number is changed by verifying another one, so the form
        // stays available either way — as it does on the web.
        const SizedBox(height: 14),
        _PhoneVerifySection(verified: private.phoneVerified),
      ],
    );
  }

  Widget _passwordSection(String email) {
    return SettingsSection(
      title: 'Ubah Password',
      description: 'Ganti password akun kamu.',
      children: [
        _PasswordField(
          controller: _currentPassword,
          label: 'Password Saat Ini',
          error: _currentPasswordError,
        ),
        const SizedBox(height: 10),
        _PasswordField(
          controller: _newPassword,
          label: 'Password Baru',
          error: _newPasswordError,
          helper: 'Minimal 8 karakter',
        ),
        const SizedBox(height: 10),
        _PasswordField(
          controller: _confirmPassword,
          label: 'Konfirmasi Password',
          error: _confirmPasswordError,
        ),
        const SizedBox(height: 10),
        _SaveButton(
          label: 'Simpan Password',
          loading: _savingPassword,
          onPressed: _savingPassword ? null : () => _savePassword(email),
        ),
      ],
    );
  }

  Widget _privacySections(String userId, CollectionVisibility? visibility) {
    final isPublic = visibility?.isPublic ?? false;
    return Column(
      children: [
        SettingsSection(
          title: 'Koleksi Publik',
          description: 'Izinkan pengguna lain melihat koleksi kartu kamu.',
          trailing: Switch.adaptive(
            value: isPublic,
            onChanged: _savingVisibility || visibility == null
                ? null
                : (next) => _toggleFlag(
                    userId: userId,
                    column: 'is_public',
                    value: next,
                    onLabel: 'Koleksi sekarang publik',
                    offLabel: 'Koleksi sekarang privat',
                    setSaving: (v) => _savingVisibility = v,
                  ),
          ),
        ),
        if (isPublic) ...[
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Tampilkan Jumlah Kartu',
            description:
                'Tampilkan jumlah duplikat kartu di koleksi publik kamu.',
            trailing: Switch.adaptive(
              value: visibility?.showQuantity ?? true,
              onChanged: _savingQuantity
                  ? null
                  : (next) => _toggleFlag(
                      userId: userId,
                      column: 'show_quantity',
                      value: next,
                      onLabel: 'Jumlah kartu ditampilkan',
                      offLabel: 'Jumlah kartu disembunyikan',
                      setSaving: (v) => _savingQuantity = v,
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bioSection(String userId) {
    return SettingsSection(
      title: 'Deskripsi Profil',
      description: 'Ceritakan sedikit tentang diri kamu.',
      children: [
        TextField(
          controller: _bio,
          maxLines: 3,
          maxLength: 150,
          decoration: const InputDecoration(
            hintText: 'Ceritakan tentang koleksi kamu...',
          ),
        ),
        const SizedBox(height: 4),
        _SaveButton(
          label: 'Simpan',
          loading: _savingBio,
          onPressed: _savingBio ? null : () => _saveBio(userId),
        ),
      ],
    );
  }

  Widget _socialSection(String userId) {
    return SettingsSection(
      title: 'Media Sosial',
      description: 'Tambahkan link media sosial kamu.',
      children: [
        _SocialField(
          controller: _whatsapp,
          icon: LucideIcons.phone,
          hint: 'Nomor WhatsApp',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 10),
        _SocialField(
          controller: _facebook,
          icon: Icons.facebook,
          hint: 'Username Facebook',
        ),
        const SizedBox(height: 10),
        _SocialField(
          controller: _instagram,
          icon: LucideIcons.camera,
          hint: 'Username Instagram',
        ),
        const SizedBox(height: 10),
        _SocialField(
          controller: _tiktok,
          icon: LucideIcons.music,
          hint: 'Username TikTok',
        ),
        const SizedBox(height: 10),
        _SocialField(controller: _x, icon: LucideIcons.x, hint: 'Username X'),
        const SizedBox(height: 10),
        _SaveButton(
          label: 'Simpan',
          loading: _savingSocial,
          onPressed: _savingSocial ? null : () => _saveSocial(userId),
        ),
      ],
    );
  }
}

/// The signed-in user, as web's sidebar heads its nav with. Ports the
/// `bg-secondary/60` identity card: avatar, then the username over the
/// email — falling back to the email's local part when no username has been
/// chosen, exactly as web does.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.email,
    this.avatarUrl,
  });

  final String name;
  final String email;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          UserAvatar(username: name, imageUrl: avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of web's settings nav. The active one is filled and takes the
/// foreground colour; the rest stay muted until tapped.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = active ? colors.onSurface : context.mutedForeground;

    return Material(
      color: active ? colors.secondary : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: active
                      ? AppTypography.bodySmSemibold(foreground)
                      : AppTypography.bodySm(foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web's "Legal" group, under its own rule and overline.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  static const _links = <({String label, String slug})>[
    (label: 'Syarat & Ketentuan', slug: 'syarat-dan-ketentuan'),
    (label: 'Kebijakan Privasi', slug: 'kebijakan-privasi'),
    (label: 'Panduan Kondisi Kartu', slug: 'kondisi-kartu'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'LEGAL',
            style: AppTypography.caption(
              context.mutedForeground.withValues(alpha: 0.6),
            ).copyWith(letterSpacing: 0.8),
          ),
        ),
        const SizedBox(height: 4),
        for (final link in _links)
          _NavItem(
            icon: LucideIcons.fileText,
            label: link.label,
            onTap: () => context.push(Routes.terms(link.slug)),
          ),
      ],
    );
  }
}

/// Ports web's `handleAvatarUpload`. The app has an image picker after all —
/// the seller storefront has used one for its logo all along; this section
/// just never got wired to it and told the user to go to the website.
class _PhotoSection extends ConsumerStatefulWidget {
  const _PhotoSection({required this.user});

  final AppUser user;

  @override
  ConsumerState<_PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends ConsumerState<_PhotoSection> {
  bool _uploading = false;

  Future<void> _pick() async {
    if (_uploading) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Web takes the file as-is under a 2MB cap, which rejects most phone
      // photos outright. Downscaling on the way in keeps the same cap while
      // letting a normal camera roll through; an avatar never renders above
      // 80px, so 1024 is already generous.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;

    final extension = picked.path.toLowerCase().endsWith('.png')
        ? 'png'
        : 'jpg';
    final error = await ref
        .read(userRepositoryProvider)
        .uploadAvatar(bytes: bytes, extension: extension);
    if (!mounted) return;

    setState(() => _uploading = false);
    if (error == null) {
      // The header, the profile page and this section all read the avatar
      // off their own provider, so all three have to be told.
      ref.invalidate(myProfileProvider);
      // Re-reads `profiles`, so the account header picks the new face up too.
      ref.invalidate(authProvider);
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Foto profil diperbarui')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return SettingsSection(
      title: 'Foto Profil',
      description: 'Foto ini ditampilkan di profil dan daftar pengguna.',
      children: [
        Row(
          children: [
            Stack(
              children: [
                UserAvatar(
                  username: user.username ?? user.email,
                  imageUrl: user.avatarUrl,
                  size: 64,
                ),
                if (_uploading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Format: JPG, PNG, WebP',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  Text(
                    'Maksimal 2MB',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pick,
                    icon: const Icon(LucideIcons.camera, size: 16),
                    label: Text(_uploading ? 'Mengunggah...' : 'Ubah Foto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ports the web settings page's `<section className="rounded-lg border
/// ... bg-secondary/30">` block — a title, a muted description, and either
/// a trailing control or a stack of fields.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.description,
    this.children = const [],
    this.trailing,
  });

  final String title;
  final String description;
  final List<Widget> children;

  /// Right-aligned control for the toggle-only sections.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.3),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodySemibold(colors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (children.isNotEmpty) ...[const SizedBox(height: 14), ...children],
        ],
      ),
    );
  }
}

class _SocialField extends StatelessWidget {
  const _SocialField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.error,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? helper;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.error,
        helperText: widget.helper,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Ports web's OTP box: type a number, receive a WhatsApp code, type it back.
///
/// Both halves go through `/api/otp/*` rather than Supabase — sending needs
/// the server's Fazpass key and verifying finishes with a `service_role`
/// RPC, so neither can run from the client.
class _PhoneVerifySection extends ConsumerStatefulWidget {
  const _PhoneVerifySection({required this.verified});

  final bool verified;

  @override
  ConsumerState<_PhoneVerifySection> createState() =>
      _PhoneVerifySectionState();
}

class _PhoneVerifySectionState extends ConsumerState<_PhoneVerifySection> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  /// The number the server normalised and actually sent to — verifying has
  /// to quote that, not whatever is still in the input.
  String? _sentTo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      // The route's own Indonesian message — rate limits, a taken number, a
      // wrong code — is better than anything restated here.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    final normalised = await ref
        .read(phoneOtpRepositoryProvider)
        .send(_phone.text);
    if (!mounted) return;
    setState(() => _sentTo = normalised);
    _toast('Kode dikirim ke $normalised');
  });

  Future<void> _verify() => _run(() async {
    await ref
        .read(phoneOtpRepositoryProvider)
        .verify(phone: _sentTo!, code: _code.text);
    if (!mounted) return;
    setState(() {
      _sentTo = null;
      _code.clear();
    });
    ref.invalidate(privateProfileProvider);
    _toast('Nomor HP terverifikasi');
  });

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final awaitingCode = _sentTo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!awaitingCode) ...[
          LabeledField(
            label: widget.verified ? 'Ganti nomor HP' : 'Nomor HP',
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              enabled: !_busy,
              // The send button reads this controller, which does not rebuild
              // on its own.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '08xxxxxxxxx',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _SaveButton(
            label: 'Kirim Kode OTP',
            loading: _busy,
            onPressed: _phone.text.trim().isEmpty ? null : _send,
          ),
        ] else ...[
          LabeledField(
            label: 'Kode OTP',
            child: TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              maxLength: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '6 digit',
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kode dikirim lewat WhatsApp ke $_sentTo.',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 10),
          _SaveButton(
            label: 'Verifikasi',
            loading: _busy,
            onPressed: _code.text.trim().length == 6 ? _verify : null,
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _sentTo = null),
            child: const Text('Ganti nomor'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: AppTypography.bodySm(context.appColors.error)),
        ],
      ],
    );
  }
}
