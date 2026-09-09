import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/profile_models.dart';
import '../usecase/user_notifier.dart';

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
  CardFilters _filters = const CardFilters();

  /// Most valuable first, as the Koleksi page opens — a profile is read as a
  /// portfolio, and what it is worth is the question it answers.
  CardSortOption _sortBy = CardSortOption.priceDesc;
  CardViewMode _viewMode = CardViewMode.grid;
  bool _savingVisibility = false;

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
                icon: LucideIcons.userX,
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
            final visible = sortCards(
              applyCardFilters(collection, _filters),
              _sortBy,
            );
            final totalOwned = collection.fold<int>(
              0,
              (sum, card) => sum + card.owned,
            );
            final totalValue = collection.fold<int>(
              0,
              (sum, card) => sum + (card.marketPrice ?? 0) * card.owned,
            );
            final contributions = contributionsAsync.valueOrNull ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _ProfileHeader(profile: profile, isOwner: isOwner),
                if (isOwner) ...[
                  const SizedBox(height: 14),
                  _PrivacyToggle(
                    icon: profile.isCollectionPublic
                        ? LucideIcons.eye
                        : LucideIcons.eyeOff,
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
                ],
                const SizedBox(height: 20),

                // The portfolio block: what the collection is worth, then
                // the same browser and grid the Koleksi page uses, so one
                // person's shelf reads the same wherever it is opened.
                if (!profile.isCollectionPublic && !isOwner)
                  const _NoticeBox(
                    icon: LucideIcons.lock,
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
                  _PortfolioHeader(
                    totalValue: totalValue,
                    uniqueCards: collection.length,
                    totalOwned: totalOwned,
                  ),
                  const SizedBox(height: 12),
                  CardFilterBar(
                    cards: collection,
                    filters: _filters,
                    onFiltersChanged: (f) => setState(() => _filters = f),
                    sortBy: _sortBy,
                    onSortChanged: (s) => setState(() => _sortBy = s),
                    viewMode: _viewMode,
                    onViewModeChanged: (v) => setState(() => _viewMode = v),
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    const _NoticeBox(
                      message: 'Tidak ada kartu yang sesuai filter.',
                    )
                  else if (_viewMode == CardViewMode.grid)
                    GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: cardGridDelegate(context),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => CardGridItem(
                        card: visible[i],
                        onTap: () => context.push(
                          Routes.cardDetail(visible[i].packSlug, visible[i].id),
                        ),
                      ),
                    )
                  else
                    for (final card in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CardListItem(
                          card: card,
                          onTap: () => context.push(
                            Routes.cardDetail(card.packSlug, card.id),
                          ),
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
            icon: LucideIcons.circleAlert,
            title: 'Gagal memuat profil',
          ),
        ),
      ),
    );
  }
}

/// "Portofolio · Rp1.270.000" — what the collection under it is worth, in
/// the shape the Koleksi page states it.
class _PortfolioHeader extends StatelessWidget {
  const _PortfolioHeader({
    required this.totalValue,
    required this.uniqueCards,
    required this.totalOwned,
  });

  final int totalValue;
  final int uniqueCards;
  final int totalOwned;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Portofolio', style: AppTypography.h3(colors.onSurface)),
              const SizedBox(height: 2),
              Text(
                '$uniqueCards kartu unik · $totalOwned total',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Total nilai',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 2),
            Text(
              // "Rp–" rather than Rp0 when nothing is priced, the same way
              // the Koleksi page puts it.
              totalValue <= 0 ? 'Rp–' : formatRupiah(totalValue),
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile, required this.isOwner});

  final PublicProfile profile;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final shop = ref.watch(profileShopProvider(profile.username)).valueOrNull;
    final stats = ref
        .watch(profileFollowStatsProvider(profile.username))
        .valueOrNull;
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
                  const SizedBox(height: 6),
                  _ProfileStats(
                    profile: profile,
                    isOwner: isOwner,
                    stats: stats,
                    shopFollowers: shop?.followersCount,
                  ),
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
        Row(
          children: [
            // Only a shop can be followed, and never your own.
            if (shop?.userId != null && !isOwner) ...[
              _FollowButton(shopUserId: shop!.userId!),
              const SizedBox(width: 8),
            ],
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(Routes.storeDetail(profile.username)),
              icon: const Icon(LucideIcons.store, size: 16),
              label: const Text('Lihat toko'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The muted "+ Tambah ..." prompt the owner sees in place of an empty bio
/// or socials, linking into settings.
/// The counts under the name: followers, what the owner follows, and the
/// card images they have contributed.
class _ProfileStats extends ConsumerWidget {
  const _ProfileStats({
    required this.profile,
    required this.isOwner,
    this.stats,
    this.shopFollowers,
  });

  final PublicProfile profile;
  final bool isOwner;

  /// Both counts, straight from `get_profile_follow_stats`.
  final ({String userId, int followers, int following})? stats;

  /// The fallback follower count, off the shop row. Only used where the RPC
  /// hasn't answered: it is the one number a client can see without it, and
  /// only for a profile that has a shop.
  final int? shopFollowers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = stats;
    // Without the RPC, "how many does this person follow" is unknowable for
    // anyone but yourself — `shop_follows` is select-own.
    final followers = counts?.followers ?? shopFollowers;
    final following =
        counts?.following ??
        (isOwner ? ref.watch(followingCountProvider) : null);

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        if (followers != null) _Stat(label: 'Pengikut', value: followers),
        if (following != null) _Stat(label: 'Mengikuti', value: following),
        if (profile.contributionCount > 0)
          _Stat(label: 'Kontribusi', value: profile.contributionCount),
      ],
    );
  }
}

/// "12 Pengikut" — the number first, since that is what is being compared.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: AppTypography.bodySmSemibold(context.appColors.onSurface),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.bodySm(context.mutedForeground)),
      ],
    );
  }
}

/// Follow / Mengikuti, against the same RPCs the storefront uses.
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.shopUserId});

  final String shopUserId;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _busy = false;

  Future<void> _toggle(bool following) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _busy = true);
    final error = await ref
        .read(followControllerProvider)
        .setFollowing(shopUserId: widget.shopUserId, following: !following);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
      return;
    }
    // The count on screen comes off the shop row, which the follow just
    // moved.
    ref.invalidate(profileShopProvider);
  }

  @override
  Widget build(BuildContext context) {
    final following =
        ref.watch(isFollowingShopProvider(widget.shopUserId)).valueOrNull ??
        false;
    final icon = _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(following ? LucideIcons.check : LucideIcons.userPlus, size: 16);

    return following
        ? ElevatedButton.icon(
            onPressed: _busy ? null : () => _toggle(following),
            icon: icon,
            label: const Text('Mengikuti'),
          )
        : OutlinedButton.icon(
            onPressed: _busy ? null : () => _toggle(following),
            icon: icon,
            label: const Text('Ikuti'),
          );
  }
}

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
            LucideIcons.plus,
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
            icon: LucideIcons.phone,
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
            icon: LucideIcons.camera,
            tooltip: 'Instagram',
            onTap: () =>
                _open('https://instagram.com/${profile.socialInstagram}'),
          ),
        if (_isSafeHandle(profile.socialTiktok))
          _SocialIcon(
            icon: LucideIcons.music,
            tooltip: 'TikTok',
            onTap: () => _open('https://tiktok.com/@${profile.socialTiktok}'),
          ),
        if (_isSafeHandle(profile.socialX))
          _SocialIcon(
            icon: LucideIcons.x,
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
