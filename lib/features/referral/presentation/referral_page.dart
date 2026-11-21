import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/design_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../usecase/referral_providers.dart';
import 'referral_share.dart';
import 'referral_style.dart';

/// Ajak Teman dashboard (design 02 §2). One `get_referral_dashboard` call
/// feeds every section; friend pages after the first are appended here.
class ReferralPage extends ConsumerStatefulWidget {
  const ReferralPage({super.key});

  @override
  ConsumerState<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends ConsumerState<ReferralPage> {
  var _filter = ReferralFilter.all;
  final _more = <ReferralFriend>[];
  bool? _moreHasMore;
  var _loadingMore = false;

  /// Bumped whenever the list is reset, so a page that lands after a filter
  /// switch or refresh is dropped instead of appended to the wrong list.
  var _generation = 0;

  /// The last dashboard shown. A filter switch is a new provider instance
  /// with no data yet; showing this meanwhile keeps the page (and the scroll
  /// position) instead of blanking it to a spinner.
  ReferralDashboard? _shown;

  /// Rows reminded this session, before the refetch catches up.
  final _reminded = <String>{};

  /// Friends whose reminder is in flight; a second tap would only get a
  /// "Sudah diingatkan" toast while the first is still opening WhatsApp.
  final _reminding = <String>{};

  @override
  void initState() {
    super.initState();
    // The Akun nav dot keeps the dashboard cached for the session; revalidate
    // on entry so a pack that arrived since then shows up.
    Future.microtask(() {
      if (mounted) ref.invalidate(referralDashboardProvider);
    });
  }

  void _resetPaging() {
    _more.clear();
    _moreHasMore = null;
    _generation++;
  }

  Future<void> _refresh() async {
    setState(_resetPaging);
    ref.invalidate(referralDashboardProvider);
    ref.invalidate(koinBalanceProvider);
    try {
      await ref.read(referralDashboardProvider(_filter).future);
    } catch (_) {
      // The page shows its own error state; nothing to rethrow into.
    }
  }

  Future<void> _loadMore(int shown) async {
    if (_loadingMore) return;
    final filter = _filter;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(referralRepositoryProvider)
          .fetchDashboard(filter: filter, offset: shown);
      if (!mounted || generation != _generation) return;
      setState(() {
        _more.addAll(page.friends);
        _moreHasMore = page.hasMore;
      });
    } catch (e) {
      debugPrint('[referral] load more failed: $e');
      _toast('Gagal memuat teman. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openPack(String id) async {
    await context.push(Routes.referralPack(id));
    if (!mounted) return;
    setState(_resetPaging);
    ref.invalidate(referralDashboardProvider);
    ref.invalidate(koinBalanceProvider);
  }

  Future<void> _remind(ReferralDashboard d, ReferralFriend friend) async {
    if (!_reminding.add(friend.refereeId)) return;
    try {
      final RemindResult result;
      try {
        result = await ref
            .read(referralRepositoryProvider)
            .markReminded(friend.refereeId);
      } on ReferralException {
        // not_remindable / not_found: the list is stale.
        _toast('Daftar temanmu sudah berubah.');
        if (mounted) await _refresh();
        return;
      } catch (e, st) {
        // Not marked, so a retry really can send it.
        debugPrint('[referral] markReminded failed: $e\n$st');
        _toast('Gagal mengirim pengingat. Coba lagi.');
        return;
      }
      if (!mounted) return;
      setState(() => _reminded.add(friend.refereeId));
      if (!result.ok) {
        final next = result.nextAllowedAt;
        _toast(
          next == null
              ? 'Sudah diingatkan.'
              : 'Sudah diingatkan. Bisa diingatkan lagi ${formatShortDateId(next)}.',
        );
        return;
      }
      // The server sent the friend an in-app notification + push.
      _toast('Pengingat terkirim ke @${friend.username}.');
    } finally {
      _reminding.remove(friend.refereeId);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final async = ref.watch(referralDashboardProvider(_filter));
    final fresh = async.valueOrNull;
    if (fresh != null) _shown = fresh;
    final dashboard = fresh ?? _shown;

    Widget body;
    if (!signedIn) {
      body = _Centered(
        EmptyState(
          icon: LucideIcons.gift,
          title: 'Masuk untuk ajak teman',
          action: ElevatedButton(
            onPressed: () => context.push(Routes.login),
            child: const Text('Masuk'),
          ),
        ),
      );
    } else if (dashboard == null && async.hasError) {
      body = _Centered(
        EmptyState(
          icon: LucideIcons.wifiOff,
          title: 'Gagal memuat Ajak Teman',
          action: OutlinedButton(
            onPressed: _refresh,
            child: const Text('Coba lagi'),
          ),
        ),
      );
    } else if (dashboard == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!dashboard.enabled) {
      body = const _Centered(
        EmptyState(
          icon: LucideIcons.gift,
          title: 'Program Ajak Teman sedang tidak aktif',
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        // The new filter's first page is still loading over the old list.
        child: _content(dashboard, switching: fresh == null),
      );
    }

    // Solid bar, not transparent: once the red header scrolls away a
    // transparent bar left white icons floating over the cards.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: signedIn ? ReferralColors.red : null,
        flexibleSpace: signedIn
            ? DecoratedBox(decoration: _redPattern())
            : null,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: signedIn ? Colors.white : null,
        systemOverlayStyle: signedIn ? SystemUiOverlayStyle.light : null,
        elevation: 0,
        title: Text(
          'Ajak Teman',
          style: AppTypography.h3(
            signedIn ? Colors.white : context.appColors.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Syarat & Ketentuan',
            icon: const Icon(LucideIcons.info),
            onPressed: () => context.push(Routes.terms('ajak-teman')),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _content(ReferralDashboard d, {bool switching = false}) {
    // Deduped by id: an offset page can repeat a row when a friend joins
    // between pages. The server offset stays the raw count.
    final friends = {
      for (final f in [...d.friends, ..._more]) f.refereeId: f,
    }.values.toList();
    final hasMore = _moreHasMore ?? d.hasMore;
    final user = ref.watch(authProvider).valueOrNull;

    return ListView(
      padding: EdgeInsets.zero,
      // Clamping, not iOS bounce: a bounce pulls the red header away from
      // the red app bar and shows the page background between them.
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      children: [
        _Header(maxPrize: d.maxPrize),
        Transform.translate(
          offset: const Offset(0, -36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _CodeCard(dashboard: d, username: user?.username ?? ''),
                if (d.readyPacks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PackReadyCard(
                    packs: d.readyPacks,
                    maxPrize: d.maxPrize,
                    onOpen: () => _openPack(d.readyPacks.first.id),
                  ),
                ],
                const SizedBox(height: 16),
                _Stats(d),
                const SizedBox(height: 24),
                _FriendsSection(
                  dashboard: d,
                  filter: _filter,
                  friends: friends,
                  hasMore: hasMore,
                  loadingMore: _loadingMore,
                  switching: switching,
                  reminded: _reminded,
                  onFilter: (f) {
                    if (f == _filter) return;
                    setState(() {
                      _filter = f;
                      _resetPaging();
                    });
                  },
                  onLoadMore: () => _loadMore(d.friends.length + _more.length),
                  onRemind: (f) => _remind(d, f),
                  onOpenPack: _openPack,
                  onShare: () => showReferralShareSheet(context, d),
                ),
                const SizedBox(height: 24),
                const _HowItWorks(),
                const SizedBox(height: 24),
                if (d.tiers.isNotEmpty) _PackContents(d.tiers),
                const SizedBox(height: 16),
                const _Notes(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(child: child));
}

BoxDecoration _redPattern({
  BorderRadius? radius,
  Color color = ReferralColors.red,
}) => BoxDecoration(
  color: color,
  borderRadius: radius,
  image: const DecorationImage(
    image: AssetImage('$referralImageDir/pattern-energi-tile-merah.webp'),
    repeat: ImageRepeat.repeat,
    scale: 2,
    opacity: 0.5,
  ),
);

class _Header extends StatelessWidget {
  const _Header({required this.maxPrize});

  final int maxPrize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _redPattern(
        radius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
      child: Column(
        children: [
          Image.asset(
            '$referralImageDir/hero-coretan.webp',
            width: 220,
            cacheWidth: (220 * MediaQuery.devicePixelRatioOf(context)).round(),
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Ajak teman, dapat hadiah sampai ${formatRupiah(maxPrize)} per teman',
            textAlign: TextAlign.center,
            style: AppTypography.h2(Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Tiap teman yang selesai belanja pertama (min. Rp30rb) = 1 Pack Hadiah buat kamu.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.dashboard, required this.username});

  final ReferralDashboard dashboard;
  final String username;

  void _toast(BuildContext context, String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m), persist: false));

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final muted = context.mutedForeground;
    final code = d.code;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kode referal kamu',
            style: GoogleFonts.urbanist(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          if (code == null)
            Text(
              'Atur username dulu untuk dapat kode referal.',
              style: AppTypography.bodySm(muted),
            )
          else ...[
            ReferralCodeBox(
              code: code,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: code));
                _toast(context, 'Kode disalin');
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ReferralColors.red,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => showReferralShareSheet(context, d),
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Bagikan kupon ke teman'),
              ),
            ),
            const SizedBox(height: 16),
            ReferralQuickShare(dashboard: d, username: username),
          ],
          const Divider(height: 32),
          Row(
            children: [
              Image.asset('$referralImageDir/kupon-coretan.webp', width: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temanmu dapat kupon gratis ongkir',
                      style: GoogleFonts.urbanist(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.appColors.onSurface,
                      ),
                    ),
                    Text(
                      's/d ${formatRupiah(d.couponMaxAmount)} untuk belanja pertama, aktif otomatis pakai kodemu',
                      style: GoogleFonts.urbanist(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackReadyCard extends StatelessWidget {
  const _PackReadyCard({
    required this.packs,
    required this.maxPrize,
    required this.onOpen,
  });

  final List<ReadyPack> packs;
  final int maxPrize;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final first = packs.first.fromUsername;
    final from = packs.length > 1
        ? 'Pack dari @$first +${packs.length - 1} lainnya'
        : 'Pack dari @$first';
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        decoration: _redPattern(
          radius: BorderRadius.circular(20),
          color: ReferralColors.maroon,
        ),
        child: Row(
          children: [
            Transform.rotate(
              angle: -0.1,
              child: Image.asset(
                '$referralImageDir/pack-hadiah-v5.webp',
                width: 52,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ReferralColors.pillGold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '● ${packs.length} PACK SIAP',
                      style: GoogleFonts.urbanist(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: ReferralColors.pillGoldText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    from,
                    style: AppTypography.bodySemibold(Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Isinya Koin hingga ${formatRupiahCompact(maxPrize)}',
                    style: AppTypography.caption(
                      Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: ReferralColors.red,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: onOpen,
              icon: const Icon(LucideIcons.gift, size: 16),
              label: const Text('Buka'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats(this.d);

  final ReferralDashboard d;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, {Color? color}) => Expanded(
      child: Column(
        children: [
          // Scaled down, not wrapped mid-number ("Rp1.250.\n000").
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppTypography.h3(color ?? context.appColors.onSurface),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
    final divider = Container(width: 1, height: 36, color: context.borderColor);
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          stat(
            formatRupiah(d.koinEarned),
            'Hadiah didapat',
            color: DesignPalette.of(context).successText,
          ),
          divider,
          stat(formatCountId(d.friendCount), 'Teman bergabung'),
          divider,
          stat(formatCountId(d.packCount), 'Pack didapat'),
        ],
      ),
    );
  }
}

class _FriendsSection extends StatelessWidget {
  const _FriendsSection({
    required this.dashboard,
    required this.filter,
    required this.friends,
    required this.hasMore,
    required this.loadingMore,
    required this.switching,
    required this.reminded,
    required this.onFilter,
    required this.onLoadMore,
    required this.onRemind,
    required this.onOpenPack,
    required this.onShare,
  });

  final ReferralDashboard dashboard;
  final ReferralFilter filter;
  final List<ReferralFriend> friends;
  final bool hasMore;
  final bool loadingMore;
  final bool switching;
  final Set<String> reminded;
  final ValueChanged<ReferralFilter> onFilter;
  final VoidCallback onLoadMore;
  final ValueChanged<ReferralFriend> onRemind;
  final ValueChanged<String> onOpenPack;
  final VoidCallback onShare;

  static const _labels = {
    ReferralFilter.all: 'Semua',
    ReferralFilter.process: 'Proses',
    ReferralFilter.packs: 'Dapat pack',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final noFriendsAtAll = (dashboard.counts[ReferralFilter.all] ?? 0) == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Teman yang kamu ajak', style: AppTypography.h3(colors.onSurface)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in ReferralFilter.values) ...[
                ChoiceChip(
                  label: Text('${_labels[f]} · ${dashboard.counts[f] ?? 0}'),
                  selected: f == filter,
                  showCheckmark: false,
                  selectedColor: colors.onSurface,
                  labelStyle: AppTypography.bodySmSemibold(
                    f == filter ? colors.surface : colors.onSurface,
                  ),
                  shape: const StadiumBorder(),
                  onSelected: (_) => onFilter(f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (switching)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (friends.isEmpty && !switching)
          _Card(
            child: Column(
              children: [
                Text(
                  noFriendsAtAll
                      ? 'Belum ada teman yang pakai kodemu. Bagikan sekarang, yuk!'
                      : 'Belum ada teman di sini.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                // No code (no username) means nothing to share yet.
                if (noFriendsAtAll && dashboard.code != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ReferralColors.red,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: onShare,
                    icon: const Icon(LucideIcons.send, size: 16),
                    label: const Text('Bagikan'),
                  ),
                ],
              ],
            ),
          )
        else
          _Card(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  for (var i = 0; i < friends.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.borderColor),
                    _FriendRow(
                      friend: friends[i],
                      reminded: reminded.contains(friends[i].refereeId),
                      onRemind: () => onRemind(friends[i]),
                      onOpenPack: onOpenPack,
                    ),
                  ],
                  if (hasMore)
                    TextButton(
                      onPressed: loadingMore ? null : onLoadMore,
                      child: Text(
                        loadingMore ? 'Memuat...' : 'Muat lebih banyak',
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.reminded,
    required this.onRemind,
    required this.onOpenPack,
  });

  final ReferralFriend friend;
  final bool reminded;
  final VoidCallback onRemind;
  final ValueChanged<String> onOpenPack;

  /// Status line per 09 §1.
  String get _statusText {
    final pack = friend.pack;
    return switch (friend.status) {
      ReferralFriendStatus.registered => 'Daftar · belum belanja',
      ReferralFriendStatus.firstOrderPaid => 'Pesanan dibayar',
      ReferralFriendStatus.firstOrderShipped => 'Pesanan dikirim',
      ReferralFriendStatus.completed => switch (pack?.status) {
        ReferralPackStatus.held => 'Menunggu verifikasi',
        ReferralPackStatus.opened => 'Pack dibuka',
        ReferralPackStatus.voided => 'Tidak memenuhi syarat',
        _ => 'Selesai belanja',
      },
      ReferralFriendStatus.expired => 'Kupon kedaluwarsa',
      ReferralFriendStatus.voided => 'Tidak memenuhi syarat',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pack = friend.pack;
    final ready =
        friend.status == ReferralFriendStatus.completed &&
        pack?.status == ReferralPackStatus.ready;

    // The cream highlight is a light-mode treatment; in dark the row keeps
    // the card colour and theme text.
    final tinted = ready && Theme.of(context).brightness == Brightness.light;

    Widget? trailing;
    if (friend.isRemindable && friend.canRemind && !reminded) {
      trailing = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onRemind,
        icon: const Icon(LucideIcons.bell, size: 14),
        label: const Text('Ingatkan'),
      );
    } else if (friend.isRemindable) {
      // Plain text, not a disabled button: the button was wide enough to
      // squeeze the username and status down to an ellipsis.
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.check, size: 14, color: context.mutedForeground),
          const SizedBox(width: 4),
          Text(
            'Diingatkan',
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
        ],
      );
    } else if (friend.status == ReferralFriendStatus.firstOrderPaid ||
        friend.status == ReferralFriendStatus.firstOrderShipped) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 14, color: context.mutedForeground),
          const SizedBox(width: 4),
          Text(
            'Menunggu',
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
        ],
      );
    } else if (ready) {
      trailing = FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: ReferralColors.red,
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => onOpenPack(pack!.id),
        icon: const Icon(LucideIcons.gift, size: 14),
        label: const Text('Buka pack'),
      );
    } else if (pack?.status == ReferralPackStatus.opened &&
        pack?.tier != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            tierThumb(pack!.tier!),
            width: 28,
            cacheWidth: (28 * MediaQuery.devicePixelRatioOf(context)).round(),
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${formatRupiah(pack.amount ?? 0)}',
                style: GoogleFonts.urbanist(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: DesignPalette.of(context).successText,
                ),
              ),
              Text(
                pack.tier!.label,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      color: tinted ? ReferralColors.codeBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          UserAvatar(username: friend.username, imageUrl: friend.avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${friend.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tinted ? ReferralColors.ink : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 14,
                        height: 4,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: i < friend.progress
                              ? ReferralColors.red
                              : context.borderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(
                          ready
                              ? ReferralColors.muted
                              : context.mutedForeground,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (LucideIcons.send, 'Bagikan kode', 'Ke teman, keluarga, atau grup TCG.'),
      (
        LucideIcons.shoppingBag,
        'Teman belanja',
        'Pakai kupon gratis ongkir di pesanan pertama.',
      ),
      (
        LucideIcons.gift,
        'Robek pack',
        'Pesanan pertama selesai (min. Rp30rb) = 1 pack buat kamu.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cara kerjanya',
          style: AppTypography.h3(context.appColors.onSurface),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _Card(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: context.appColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            steps[i].$1,
                            size: 16,
                            color: context.appColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          steps[i].$2,
                          style: AppTypography.bodySmSemibold(
                            context.appColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          steps[i].$3,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PackContents extends StatelessWidget {
  const _PackContents(this.tiers);

  final List<ReferralTier> tiers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Isi Pack Hadiah',
                style: AppTypography.h3(context.appColors.onSurface),
              ),
            ),
            Text(
              '1 hadiah Koin per pack',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [for (final t in tiers) TierOddsRow(t)]),
        ),
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.coins,
                size: 20,
                color: ReferralColors.pillGoldText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hadiah masuk sebagai Koin Pokepedia',
                      style: AppTypography.bodySmSemibold(ReferralColors.ink),
                    ),
                    Text(
                      '1 Koin = Rp1. Bisa dipakai belanja di Pokepedia, berlaku 12 bulan, tidak bisa ditarik ke rekening.',
                      style: AppTypography.caption(ReferralColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => context.push(Routes.terms('ajak-teman')),
          icon: const Icon(LucideIcons.fileText, size: 16),
          label: const Text('Baca Syarat & Ketentuan'),
        ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}
