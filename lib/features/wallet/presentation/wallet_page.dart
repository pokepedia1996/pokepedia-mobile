import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../repository/models/wallet_models.dart';
import '../usecase/wallet_notifier.dart';

/// Ports `app/wallet/page.tsx` — `components/wallet/saldo-card.tsx` +
/// `activity-feed.tsx`.
class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final activityAsync = ref.watch(walletActivityProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Saldo')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.primary, colors.primary.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saldo pokepedia.id',
                    style: AppTypography.bodySm(colors.onPrimary.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 8),
                  balanceAsync.when(
                    data: (balance) => Text(
                      formatRupiah(balance),
                      style: AppTypography.h1(colors.onPrimary),
                    ),
                    loading: () => SizedBox(
                      height: 32,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    error: (_, __) => Text('Rp-', style: AppTypography.h1(colors.onPrimary)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _showWithdrawSheet(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.onPrimary,
                        side: BorderSide(color: colors.onPrimary.withValues(alpha: 0.6)),
                      ),
                      child: const Text('Tarik Saldo'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Riwayat Aktivitas', style: AppTypography.h3(colors.onSurface)),
            const SizedBox(height: 10),
            activityAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum ada aktivitas',
                  );
                }
                return Column(
                  children: [
                    for (final item in items) _ActivityTile(activity: item),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text('Gagal memuat aktivitas'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tarik Saldo', style: AppTypography.h3(context.appColors.onSurface)),
            const SizedBox(height: 12),
            const TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dana akan dikirim ke rekening bank yang terdaftar dalam 1-2 hari kerja.',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Ajukan Penarikan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final WalletActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isCredit = activity.isCredit;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isCredit ? context.appSemantic.success : colors.error)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
              color: isCredit ? context.appSemantic.success : colors.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(activity.date, style: AppTypography.caption(context.mutedForeground)),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${formatRupiah(activity.amount)}',
            style: AppTypography.bodySmSemibold(
              isCredit ? context.appSemantic.success : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
