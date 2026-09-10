import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../usecase/payout_pricing.dart';
import '../../usecase/wallet_notifier.dart';

/// Opens the payout form. Resolves true when a withdrawal was requested.
Future<bool?> showWithdrawSheet(
  BuildContext context, {
  required int balance,
  required List<WithdrawalDestination> destinations,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) =>
        _WithdrawSheet(balance: balance, destinations: destinations),
  );
}

/// Ports `features/wallet/components/withdraw-modal.tsx` — pick an account,
/// name an amount, see the fee come off it, submit.
class _WithdrawSheet extends ConsumerStatefulWidget {
  const _WithdrawSheet({required this.balance, required this.destinations});

  final int balance;
  final List<WithdrawalDestination> destinations;

  @override
  ConsumerState<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<_WithdrawSheet> {
  late final TextEditingController _amount;
  int? _destinationId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _destinationId = defaultDestinationOf(widget.destinations)?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  WithdrawalDestination? get _selected {
    for (final destination in widget.destinations) {
      if (destination.id == _destinationId) return destination;
    }
    return null;
  }

  int get _amountValue =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  int get _fee =>
      _selected == null ? 0 : estimateXenditPayoutFee(_selected!.bankCode);

  /// The smallest request that still leaves [kMinWithdrawal] after the fee.
  int get _minGross => kMinWithdrawal + _fee;

  bool get _valid =>
      _selected != null &&
      _amountValue >= _minGross &&
      _amountValue <= widget.balance;

  Future<void> _submit() async {
    final destination = _selected;
    if (destination == null) {
      setState(() => _error = 'Pilih rekening tujuan');
      return;
    }
    if (_amountValue < _minGross) {
      setState(() => _error = 'Minimum ${formatRupiah(_minGross)}');
      return;
    }
    if (_amountValue > widget.balance) {
      setState(() => _error = 'Saldo tidak cukup');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await ref
        .read(walletRepositoryProvider)
        .requestWithdrawal(amount: _amountValue, destinationId: destination.id);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    ref.invalidate(walletBalanceProvider);
    // The debit lands in the ledger as soon as the payout is accepted, so the
    // feed behind the sheet is already stale.
    ref.invalidate(walletActivityProvider);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Penarikan sedang diproses')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final speed = describePayoutSpeed(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tarik Dana',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
            Text(
              speed.eta,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            Text(
              'Pilih Rekening',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 6),
            for (final destination in widget.destinations)
              _DestinationOption(
                destination: destination,
                selected: destination.id == _destinationId,
                onTap: _submitting
                    ? null
                    : () => setState(() => _destinationId = destination.id),
              ),
            const SizedBox(height: 16),
            Text(
              'Jumlah',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [_RupiahInputFormatter()],
              style: AppTypography.body(colors.onSurface),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Minimum ${formatRupiah(_minGross)}',
                suffixIcon: TextButton(
                  onPressed: _submitting || widget.balance < _minGross
                      ? null
                      : () {
                          _amount.value = _RupiahInputFormatter.valueFor(
                            widget.balance,
                          );
                          setState(() {});
                        },
                  child: Text(
                    'Max',
                    style: AppTypography.captionSemibold(colors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Saldo tersedia: ${formatRupiah(widget.balance)}',
              style: AppTypography.caption(context.mutedForeground),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    _SummaryRow(
                      label: 'Jumlah ditarik',
                      value: formatRupiah(_amountValue),
                    ),
                    const SizedBox(height: 4),
                    _SummaryRow(
                      label: 'Biaya admin',
                      value: '- ${formatRupiah(_fee)}',
                    ),
                    const SizedBox(height: 4),
                    _SummaryRow(
                      label: 'Diterima ke rekening',
                      value: formatRupiah(
                        _amountValue - _fee < 0 ? 0 : _amountValue - _fee,
                      ),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTypography.caption(colors.error)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _valid && !_submitting ? _submit : null,
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : const Text('Tarik'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationOption extends StatelessWidget {
  const _DestinationOption({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final WithdrawalDestination destination;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.secondary : Colors.transparent,
            border: Border.all(
              color: selected
                  ? colors.onSurface.withValues(alpha: 0.4)
                  : context.borderColor,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.primary : context.borderColor,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      '${destination.bankName} ${destination.maskedAccount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.caption(context.mutedForeground)),
        Text(
          value,
          style: emphasize
              ? AppTypography.bodySmSemibold(colors.onSurface)
              : AppTypography.bodySm(colors.onSurface),
        ),
      ],
    );
  }
}

/// Types the amount back as "Rp 1.250.000" while it is entered, the way the
/// web input reformats on every keystroke.
class _RupiahInputFormatter extends TextInputFormatter {
  static final _thousands = RegExp(r'(\d)(?=(\d{3})+$)');

  static String format(int amount) =>
      'Rp ${amount.toString().replaceAllMapped(_thousands, (m) => '${m[1]}.')}';

  /// The controller value for [amount], caret parked at the end.
  static TextEditingValue valueFor(int amount) {
    final text = format(amount);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    return valueFor(int.parse(digits));
  }
}
