import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/profile_models.dart';
import '../usecase/user_notifier.dart';
import 'users_search_page.dart' show ContributorBadge;

/// How many cards each expansion shows before "Lihat Semua", matching web's
/// `CARDS_PER_EXPANSION`.
const _cardsPerExpansion = 20;

/// Ports `app/user/[username]/page.tsx` — a public collector profile: the
/// identity header with socials, the owner's privacy toggles, the
/// expansion-grouped collection, and the contributed-artwork grid.
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.username});

  final String username;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  String _search = '';
  bool _savingVisibility = false;
  bool _savingQuantity = false;

  Future<void> _toggleProfileFlag({
    required String column,
    required bool value,
    required String onLabel,
    required String offLabel,
    required void Function(bool) setSaving,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() => setSaving(true));
    final error = await ref.read(userRepositoryProvider).updateProfile(
      user.id,
      {column: value},
    );
    if (!mounted) return;
    setState(() => setSaving(false));
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (error != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan pengaturan')),
      );
      return;
    }
    ref.invalidate(userProfileProvider(widget.username));
    messenger.showSnackBar(SnackBar(content: Text(value ? onLabel : offLabel)));
  }

  /// Web's collection search: matches card name, number, rarity, expansion
  /// code or expansion name, dropping expansions with no remaining cards.
  List<CollectionExpansionGroup> _filter(
    List<CollectionExpansionGroup> collection,
  ) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return collection;
    final out = <CollectionExpansionGroup>[];
    for (final expansion in collection) {
      final cards = expansion.cards.where((card) {
        return card.name.toLowerCase().contains(query) ||
            card.number.toLowerCase().contains(query) ||
            (card.rarity?.toLowerCase().contains(query) ?? false) ||
            expansion.slug.contains(query) ||
            expansion.expansionName.toLowerCase().contains(query);
      }).toList();
      if (cards.isNotEmpty) out.add(expansion.withCards(cards));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final profileAsync = ref.watch(userProfileProvider(widget.username));
    final viewer = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: profileAsync.when(
          data: (profile) {
            if (profile == null) {
              return EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Pengguna tidak ditemukan',
                description:
                    'Tidak ada pengguna dengan username "${widget.username}"',
                action: TextButton(
                  onPressed: () => context.push(Routes.users),
                  child: const Text('Cari pengguna lain'),
                ),
              );
            }

            final isOwner = viewer?.id == profile.userId;
            final collectionAsync = ref.watch(
              userCollectionProvider(widget.username),
            );
            final contributionsAsync = ref.watch(
              userContributionsProvider(widget.username),
            );
            final collection = collectionAsync.valueOrNull ?? const [];
            final filtered = _filter(collection);
            final totalOwned = collection.fold<int>(
              0,
              (sum, e) => sum + e.ownedCount,
            );
            final filteredOwned = filtered.fold<int>(
              0,
              (sum, e) => sum + e.ownedCount,
            );
            final contributions = contributionsAsync.valueOrNull ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _ProfileHeader(profile: profile, isOwner: isOwner),
                if (isOwner) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _PrivacyToggle(
                        icon: profile.isCollectionPublic
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        label: 'Koleksi Publik',
                        value: profile.isCollectionPublic,
                        disabled: _savingVisibility,
                        onChanged: (next) => _toggleProfileFlag(
                          column: 'is_collection_public',
                          value: next,
                          onLabel: 'Koleksi sekarang publik',
                          offLabel: 'Koleksi sekarang privat',
                          setSaving: (v) => _savingVisibility = v,
                        ),
                      ),
                      if (profile.isCollectionPublic) ...[
                        const SizedBox(width: 16),
                        _PrivacyToggle(
                          icon: Icons.tag,
                          label: 'Jumlah',
                          value: profile.showCollectionQuantity,
                          disabled: _savingQuantity,
                          onChanged: (next) => _toggleProfileFlag(
                            column: 'show_collection_quantity',
                            value: next,
                            onLabel: 'Jumlah kartu ditampilkan',
                            offLabel: 'Jumlah kartu disembunyikan',
                            setSaving: (v) => _savingQuantity = v,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text('Koleksi', style: AppTypography.h3(colors.onSurface)),
                if (!profile.isCollectionPublic && !isOwner)
                  const _NoticeBox(
                    icon: Icons.lock_outline,
                    message: 'Koleksi pengguna ini bersifat privat',
                  )
                else if (collectionAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: PikachuLoader(size: 120),
                  )
                else if (collection.isEmpty)
                  const _NoticeBox(message: 'Pengguna ini belum memiliki kartu')
                else ...[
                  const SizedBox(height: 4),
                  Text(
                    filteredOwned == totalOwned
                        ? '$totalOwned kartu dari ${collection.length} ekspansi'
                        : '$filteredOwned dari $totalOwned kartu',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      hintText:
                          'Cari nama, nomor, ekspansi, atau kelangkaan...',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    const _NoticeBox(
                      message: 'Tidak ada kartu yang sesuai filter.',
                    )
                  else
                    for (final expansion in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ExpansionGroup(
                          expansion: expansion,
                          showQuantity: profile.showCollectionQuantity,
                        ),
                      ),
                ],
                if (contributions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Kontribusi', style: AppTypography.h3(colors.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    '${contributions.length} kartu',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  const SizedBox(height: 12),
                  _ContributionsSection(contributions: contributions),
                ],
              ],
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const EmptyState(
            icon: Icons.error_outline,
            title: 'Gagal memuat profil',
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.isOwner});

  final PublicProfile profile;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              username: profile.username,
              imageUrl: profile.avatarUrl,
              size: 72,
              ring: true,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h2(colors.onSurface),
                  ),
                  if (profile.contributionCount > 0) ...[
                    const SizedBox(height: 4),
                    ContributorBadge(
                      count: profile.contributionCount,
                      large: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (profile.bio != null)
          Text(
            profile.bio!,
            style: AppTypography.bodySm(context.mutedForeground),
          )
        else if (isOwner)
          _AddHint(label: 'Tambah deskripsi'),
        if (profile.hasSocials) ...[
          const SizedBox(height: 10),
          _SocialLinks(profile: profile),
        ] else if (isOwner) ...[
          const SizedBox(height: 6),
          _AddHint(label: 'Tambah media sosial'),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.push(Routes.storeDetail(profile.username)),
            icon: const Icon(Icons.storefront_outlined, size: 16),
            label: const Text('Lihat toko'),
          ),
        ),
      ],
    );
  }
}

/// The muted "+ Tambah ..." prompt the owner sees in place of an empty bio
/// or socials, linking into settings.
class _AddHint extends StatelessWidget {
  const _AddHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.settings),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add,
            size: 14,
            color: context.mutedForeground.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.bodySm(
              context.mutedForeground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialLinks extends StatelessWidget {
  const _SocialLinks({required this.profile});

  final PublicProfile profile;

  /// Ports `isSafeHandle` — only plain handles become links, so a stored
  /// value can't smuggle a path or query into the opened URL.
  static bool _isSafeHandle(String? handle) {
    if (handle == null || handle.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9_.]{1,30}$').hasMatch(handle);
  }

  void _open(String url) {
    launcher.launchUrl(
      Uri.parse(url),
      mode: launcher.LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = profile.socialWhatsapp?.replaceAll(RegExp(r'\D'), '');
    return Row(
      children: [
        if (whatsapp != null && whatsapp.isNotEmpty)
          _SocialIcon(
            icon: Icons.phone_outlined,
            tooltip: 'WhatsApp',
            onTap: () => _open('https://wa.me/$whatsapp'),
          ),
        if (_isSafeHandle(profile.socialFacebook))
          _SocialIcon(
            icon: Icons.facebook,
            tooltip: 'Facebook',
            onTap: () =>
                _open('https://facebook.com/${profile.socialFacebook}'),
          ),
        if (_isSafeHandle(profile.socialInstagram))
          _SocialIcon(
            icon: Icons.camera_alt_outlined,
            tooltip: 'Instagram',
            onTap: () =>
                _open('https://instagram.com/${profile.socialInstagram}'),
          ),
        if (_isSafeHandle(profile.socialTiktok))
          _SocialIcon(
            icon: Icons.music_note_outlined,
            tooltip: 'TikTok',
            onTap: () => _open('https://tiktok.com/@${profile.socialTiktok}'),
          ),
        if (_isSafeHandle(profile.socialX))
          _SocialIcon(
            icon: Icons.close,
            tooltip: 'X',
            onTap: () => _open('https://x.com/${profile.socialX}'),
          ),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18, color: context.mutedForeground),
      ),
    );
  }
}

/// Ports the profile page's `PrivacyToggle` — a labelled switch the owner
/// uses to flip collection visibility without leaving the page.
class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.mutedForeground),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption(context.mutedForeground)),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.75,
          child: Switch.adaptive(
            value: value,
            onChanged: disabled ? null : onChanged,
          ),
        ),
      ],
    );
  }
}

class _ExpansionGroup extends StatefulWidget {
  const _ExpansionGroup({required this.expansion, required this.showQuantity});

  final CollectionExpansionGroup expansion;
  final bool showQuantity;

  @override
  State<_ExpansionGroup> createState() => _ExpansionGroupState();
}

class _ExpansionGroupState extends State<_ExpansionGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final expansion = widget.expansion;
    final hasMore = expansion.cards.length > _cardsPerExpansion;
    final visible = _expanded || !hasMore
        ? expansion.cards
        : expansion.cards.take(_cardsPerExpansion).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expansion.packImage != null) ...[
                InkWell(
                  onTap: () => context.push(Routes.packDetail(expansion.slug)),
                  child: Image.network(
                    expansion.packImage!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                context.push(Routes.packDetail(expansion.slug)),
                            child: Text(
                              expansion.expansionName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${expansion.progressPercent}%',
                          style: AppTypography.bodySmSemibold(colors.primary),
                        ),
                      ],
                    ),
                    Text(
                      '${expansion.ownedCount}/${expansion.totalCards} kartu',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: expansion.progressPercent / 100,
                        minHeight: 6,
                        backgroundColor: colors.secondary,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 245 / 342,
            ),
            itemBuilder: (context, i) => _CollectionThumb(
              card: visible[i],
              packSlug: expansion.slug,
              showQuantity: widget.showQuantity,
            ),
          ),
          if (hasMore && !_expanded) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text(
                'Lihat Semua (+${expansion.cards.length - _cardsPerExpansion} kartu)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionThumb extends StatelessWidget {
  const _CollectionThumb({
    required this.card,
    required this.packSlug,
    required this.showQuantity,
  });

  final CollectionCardEntry card;
  final String packSlug;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.cardDetail(packSlug, card.cardId)),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Stack(
        children: [
          CardArt(imageUrl: card.imageUrl, borderRadius: AppRadius.sm),
          if (showQuantity && card.quantity > 1)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: context.appColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '×${card.quantity}',
                  style: AppTypography.badge(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContributionsSection extends StatefulWidget {
  const _ContributionsSection({required this.contributions});

  final List<ContributionCardEntry> contributions;

  @override
  State<_ContributionsSection> createState() => _ContributionsSectionState();
}

class _ContributionsSectionState extends State<_ContributionsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.contributions;
    final hasMore = all.length > _cardsPerExpansion;
    final visible = _expanded || !hasMore
        ? all
        : all.take(_cardsPerExpansion).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 245 / 342,
            ),
            itemBuilder: (context, i) {
              final card = visible[i];
              return InkWell(
                onTap: () =>
                    context.push(Routes.cardDetail(card.packSlug, card.cardId)),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: CardArt(
                  imageUrl: card.imageUrl,
                  borderRadius: AppRadius.sm,
                ),
              );
            },
          ),
          if (hasMore && !_expanded) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text(
                'Lihat Semua (+${all.length - _cardsPerExpansion} kartu)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bordered notice web uses for the private/empty/no-match collection
/// states.
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.3),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 36,
              color: context.mutedForeground.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}
