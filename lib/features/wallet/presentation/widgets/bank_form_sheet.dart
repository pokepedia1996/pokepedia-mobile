import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../usecase/wallet_notifier.dart';

/// Opens the add/edit payout account form. Resolves true when one was saved.
Future<bool?> showBankFormSheet(
  BuildContext context, {
  WithdrawalDestination? destination,
  required bool hasAnyDestination,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _BankFormSheet(
      destination: destination,
      hasAnyDestination: hasAnyDestination,
    ),
  );
}

/// Ports `features/wallet/components/add-bank-modal.tsx`.
class _BankFormSheet extends ConsumerStatefulWidget {
  const _BankFormSheet({
    required this.destination,
    required this.hasAnyDestination,
  });

  final WithdrawalDestination? destination;

  /// Web only offers "Jadikan default" once a first account exists — the
  /// first one is the default by definition.
  final bool hasAnyDestination;

  @override
  ConsumerState<_BankFormSheet> createState() => _BankFormSheetState();
}

class _BankFormSheetState extends ConsumerState<_BankFormSheet> {
  late final TextEditingController _accountNumber;
  late final TextEditingController _holderName;
  String? _bankCode;
  bool _setDefault = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.destination != null;

  @override
  void initState() {
    super.initState();
    final destination = widget.destination;
    _bankCode = destination?.bankCode;
    _accountNumber = TextEditingController(
      text: destination?.accountNumber ?? '',
    );
    _holderName = TextEditingController(
      text: destination?.accountHolderName ?? '',
    );
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _holderName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bankCode = _bankCode;
    if (bankCode == null) {
      setState(() => _error = 'Pilih bank terlebih dahulu');
      return;
    }
    if (_accountNumber.text.trim().length < 5) {
      setState(() => _error = 'Nomor rekening minimal 5 digit');
      return;
    }
    if (_holderName.text.trim().isEmpty) {
      setState(() => _error = 'Isi nama pemilik rekening');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(walletRepositoryProvider);
    final destination = widget.destination;
    final error = destination != null
        ? await repository.updateDestination(
            id: destination.id,
            bankCode: bankCode,
            accountNumber: _accountNumber.text.trim(),
            accountHolderName: _holderName.text.trim(),
          )
        : await repository.addDestination(
            bankCode: bankCode,
            accountNumber: _accountNumber.text.trim(),
            accountHolderName: _holderName.text.trim(),
            setDefault: _setDefault,
          );

    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    ref.invalidate(walletDestinationsProvider);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Rekening diperbarui' : 'Rekening tersimpan'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
                    _isEdit ? 'Ubah Rekening' : 'Tambah Rekening',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
            Text(
              'Rekening tujuan penarikan dana saldo kamu.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _bankCode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bank'),
              hint: const Text('Pilih bank'),
              items: [
                for (final bank in indonesianBanks)
                  DropdownMenuItem(value: bank.code, child: Text(bank.name)),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _bankCode = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accountNumber,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(25),
              ],
              decoration: const InputDecoration(
                labelText: 'Nomor Rekening',
                hintText: 'mis. 1234567890',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _holderName,
              enabled: !_saving,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama Pemilik Rekening',
                hintText: 'Nama sesuai rekening bank',
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sesuai nama di buku tabungan/rekening bank. Nama berbeda bisa '
              'menyebabkan penarikan gagal.',
              style: AppTypography.caption(context.mutedForeground),
            ),
            if (!_isEdit && widget.hasAnyDestination) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: _saving
                    ? null
                    : () => setState(() => _setDefault = !_setDefault),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _setDefault,
                          onChanged: _saving
                              ? null
                              : (_) =>
                                    setState(() => _setDefault = !_setDefault),
                          activeColor: colors.primary,
                          side: BorderSide(
                            color: context.borderColor,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Jadikan default',
                        style: AppTypography.bodySm(colors.onSurface),
                      ),
                    ],
                  ),
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : Text(_isEdit ? 'Simpan Perubahan' : 'Simpan'),
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
