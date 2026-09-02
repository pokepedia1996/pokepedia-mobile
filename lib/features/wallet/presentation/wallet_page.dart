import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/payout_pricing.dart';
import '../usecase/wallet_notifier.dart';
import 'widgets/bank_form_sheet.dart';
import 'widgets/withdraw_sheet.dart';

/// Ports `app/wallet/page.tsx` — the saldo card, the saved payout accounts
/// (`bank-list.tsx`) and the ledger (`activity-feed.tsx`), stacked instead of
/// sat in web's two-column grid.
class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(walletBalanceProvider);
            ref.invalidate(walletDestinationsProvider);
            ref.invalidate(walletActivityProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  Icon(LucideIcons.wallet, size: 20, color: colors.onSurface),
                  const SizedBox(width: 8),
                  Text('Saldo', style: AppTypography.h2(colors.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              if (!signedIn)
                EmptyState(
                  icon: LucideIcons.wallet,
                  title: 'Masuk untuk melihat saldo',
                  description: 'Silakan masuk untuk melihat saldo kamu.',
                  action: ElevatedButton(
                    onPressed: () => context.push(Routes.login),
                    child: const Text('Masuk'),
                  ),
                )
              else ...[
                const _SaldoCard(),
                const SizedBox(height: 16),
                const _BankListCard(),
                const SizedBox(height: 16),
                const _ActivityFeedCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The card the page opens on: what is available, and the one button that
/// moves it. The reason a payout is blocked sits under the button rather
/// than hiding behind a disabled control, as on web.
class _SaldoCard extends ConsumerWidget {
  const _SaldoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final balance = ref.watch(walletBalanceProvider).valueOrNull ?? 0;
    final destinations =
        ref.watch(walletDestinationsProvider).valueOrNull ?? const [];

    // The fee depends on which account the money goes to, so the threshold
    // quoted here is the default account's — the one the sheet preselects.
    final fee = estimateXenditPayoutFee(
      defaultDestinationOf(destinations)?.bankCode,
    );
    final minGross = kMinWithdrawal + fee;
    final canWithdraw = destinations.isNotEmpty && balance >= minGross;
    final blockedReason = destinations.isEmpty
        ? 'Tambahkan rekening bank dulu untuk menarik dana.'
        : balance < minGross
        ? 'Minimum penarikan ${formatRupiah(minGross)} (sudah termasuk biaya '
              'admin).'
        : null;

    return _WalletCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Saldo Tersedia',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 4),
          ref
              .watch(walletBalanceProvider)
              .when(
                data: (value) => Text(
                  formatRupiah(value),
                  style: AppTypography.h1(colors.onSurface),
                ),
                loading: () => SizedBox(
                  height: 38,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.mutedForeground,
                      ),
                    ),
                  ),
                ),
                error: (_, __) =>
                    Text('Rp-', style: AppTypography.h1(colors.onSurface)),
              ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: canWithdraw
                ? () => showWithdrawSheet(
                    context,
                    balance: balance,
                    destinations: destinations,
                  )
                : null,
            icon: const Icon(LucideIcons.arrowDownToLine, size: 16),
            label: const Text('Tarik Dana'),
          ),
          if (blockedReason != null) ...[
            const SizedBox(height: 8),
            Text(
              blockedReason,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

/// Web's `BankList` — the accounts a payout can land in, and the actions on
/// each of them.
class _BankListCard extends ConsumerWidget {
  const _BankListCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final destinationsAsync = ref.watch(walletDestinationsProvider);
    final destinations = destinationsAsync.valueOrNull ?? const [];

    return _WalletCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.building2, size: 16, color: colors.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rekening Bank',
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              TextButton.icon(
                onPressed: () => showBankFormSheet(
                  context,
                  hasAnyDestination: destinations.isNotEmpty,
                ),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Tambah'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          destinationsAsync.when(
            data: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Belum ada rekening bank tersimpan',
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  )
                : Column(
                    children: [
                      for (final destination in rows)
                        _DestinationRow(
                          destination: destination,
                          hasAnyDestination: rows.isNotEmpty,
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Gagal memuat rekening',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationRow extends ConsumerStatefulWidget {
  const _DestinationRow({
    required this.destination,
    required this.hasAnyDestination,
  });

  final WithdrawalDestination destination;
  final bool hasAnyDestination;

  @override
  ConsumerState<_DestinationRow> createState() => _DestinationRowState();
}

class _DestinationRowState extends ConsumerState<_DestinationRow> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(walletDestinationsProvider);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final destination = widget.destination;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: destination.isDefault
                ? colors.onSurface.withValues(alpha: 0.2)
                : context.borderColor.withValues(alpha: 0.6),
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          destination.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                      ),
                      if (destination.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            'Default',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${destination.bankName} ${destination.maskedAccount} · '
                    '${destination.accountHolderName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: Icon(
                  LucideIcons.ellipsisVertical,
                  size: 18,
                  color: context.mutedForeground,
                ),
                position: PopupMenuPosition.under,
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: context.borderColor),
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      showBankFormSheet(
                        context,
                        destination: destination,
                        hasAnyDestination: widget.hasAnyDestination,
                      );
                    case 'default':
                      _run(
                        () => ref
                            .read(walletRepositoryProvider)
                            .setDefaultDestination(destination.id),
                        'Rekening default diperbarui',
                      );
                    case 'delete':
                      // Web deletes on the spot; a phone asks first, the way
                      // every other destructive row in the app does.
                      showConfirmDialog(
                        context,
                        title: 'Hapus rekening ini?',
                        description:
                            '${destination.bankName} '
                            '${destination.maskedAccount} akan dihapus dari '
                            'daftar tujuan penarikan.',
                        onConfirm: () => _run(
                          () => ref
                              .read(walletRepositoryProvider)
                              .deleteDestination(destination.id),
                          'Rekening dihapus',
                        ),
                      );
                  }
                },
                itemBuilder: (context) => [
                  _menuItem('edit', LucideIcons.pencil, 'Edit', context),
                  if (!destination.isDefault)
                    _menuItem(
                      'default',
                      LucideIcons.star,
                      'Jadikan default',
                      context,
                    ),
                  _menuItem(
                    'delete',
                    LucideIcons.trash2,
                    'Hapus',
                    context,
                    tone: colors.error,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    BuildContext context, {
    Color? tone,
  }) {
    final color = tone ?? context.appColors.onSurface;
    return PopupMenuItem(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: AppTypography.bodySm(color)),
        ],
      ),
    );
  }
}

/// Web's `ActivityFeed` — the ledger under its bucket tabs, one page at a
/// time.
class _ActivityFeedCard extends ConsumerStatefulWidget {
  const _ActivityFeedCard();

  @override
  ConsumerState<_ActivityFeedCard> createState() => _ActivityFeedCardState();
}

class _ActivityFeedCardState extends ConsumerState<_ActivityFeedCard> {
  WalletBucket _bucket = WalletBucket.all;

  /// Pages past the first, which the provider owns. Kept here so loading one
  /// more does not refetch the ones already on screen.
  final _more = <WalletActivity>[];
  bool _loadingMore = false;
  bool _exhausted = false;

  void _selectBucket(WalletBucket bucket) {
    if (bucket == _bucket) return;
    setState(() {
      _bucket = bucket;
      _more.clear();
      _exhausted = false;
    });
  }

  Future<void> _loadMore(List<WalletActivity> shown) async {
    if (_loadingMore || shown.isEmpty) return;
    setState(() => _loadingMore = true);
    final next = await ref
        .read(walletRepositoryProvider)
        .fetchActivity(
          bucket: _bucket,
          limit: walletActivityPageSize,
          beforeId: shown.last.id,
        );
    if (!mounted) return;
    setState(() {
      _more.addAll(next);
      _exhausted = next.length < walletActivityPageSize;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final firstPageAsync = ref.watch(walletActivityProvider(_bucket));
    final firstPage = firstPageAsync.valueOrNull ?? const <WalletActivity>[];
    // Deduped by ledger id: a refresh (after a payout, say) reloads the first
    // page against pages already held, and a new row shifts what was on the
    // boundary into both halves.
    final rows = {
      for (final activity in [...firstPage, ..._more]) activity.id: activity,
    }.values.toList();
    final hasMore =
        !_exhausted &&
        firstPage.length == walletActivityPageSize &&
        rows.isNotEmpty;

    return _WalletCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.history, size: 16, color: colors.onSurface),
              const SizedBox(width: 8),
              Text(
                'Riwayat Saldo',
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final bucket in WalletBucket.values)
                _BucketChip(
                  label: bucket.labelId,
                  active: bucket == _bucket,
                  onTap: () => _selectBucket(bucket),
                ),
            ],
          ),
          const SizedBox(height: 12),
          firstPageAsync.when(
            data: (_) => rows.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.receipt,
                    title: 'Belum ada aktivitas',
                    description:
                        'Pencairan escrow, refund dan penarikan tercatat di '
                        'sini.',
                  )
                : Column(
                    children: [
                      for (final activity in rows)
                        _ActivityRow(activity: activity),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _loadingMore
                                  ? null
                                  : () => _loadMore(rows),
                              child: Text(
                                _loadingMore
                                    ? 'Memuat...'
                                    : 'Muat lebih banyak',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: PikachuLoader(),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Gagal memuat aktivitas',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.onSurface : colors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: AppTypography.caption(
            active ? colors.surface : context.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final WalletActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final notes = activity.notes;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  if (notes != null && notes.isNotEmpty)
                    Text(
                      notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  Text(
                    activity.dateLabel,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${activity.isCredit ? '+' : ''}'
                  '${formatRupiah(activity.amount.abs())}',
                  style: AppTypography.bodySmSemibold(
                    activity.isCredit
                        ? context.appSemantic.success
                        : colors.onSurface,
                  ),
                ),
                Text(
                  'Sisa ${formatRupiah(activity.balanceAfter)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The bordered panel each section sits in — web's
/// `rounded-lg border border-border bg-card`.
class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }
}
