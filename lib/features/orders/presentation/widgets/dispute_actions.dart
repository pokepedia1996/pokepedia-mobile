import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/utils/price_input_formatter.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../seller/repository/shipment_repository.dart';
import '../../../seller/usecase/seller_order_detail_notifier.dart';
import '../../repository/disputes_repository.dart';
import '../../repository/models/dispute_model.dart';
import '../../repository/models/open_dispute.dart';
import '../../usecase/orders_notifier.dart';
import '../../utils/dispute_gating.dart';
import '../../utils/dispute_reasons.dart';

/// What the buyer can do on a dispute — web's `BuyerDisputeActions`.
class BuyerDisputeActionsPanel extends StatelessWidget {
  const BuyerDisputeActionsPanel({super.key, required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final s = BuyerDisputeActions.of(dispute);
    if (!s.isActive) return const SizedBox.shrink();
    final itemSlug = dispute.item?.slug;

    return _Stack([
      if (s.hasPartialOffer) _PartialOfferDecision(dispute: dispute),
      if (s.awaitingReturnWindow) _ReturnRequestDecision(dispute: dispute),
      if (s.returnApproved)
        const _Note(
          title: 'Retur disetujui',
          body:
              'Menunggu keputusan semua barang dalam paket sebelum kamu '
              'bisa kirim resi.',
        ),
      if (s.needsReturnTracking) _ReturnTrackingForm(dispute: dispute),
      if (s.canRespond) DisputeResponseForm(dispute: dispute),
      if (s.waitingForSeller)
        const _Note(
          title: 'Menunggu penjual',
          body: 'Respon kamu sudah terkirim. Tunggu tanggapan penjual.',
        ),
      if (s.answersAdminRequest) _AdminEvidenceRequest(dispute: dispute),
      if (s.inAdminReview && !s.answersAdminRequest) const _AdminReviewNote(),
      if (s.canWithdraw && itemSlug != null && itemSlug.isNotEmpty)
        _WithdrawButton(dispute: dispute, itemSlug: itemSlug),
    ]);
  }
}

/// What the seller can do on a dispute — web's `SellerDisputeActions`.
class SellerDisputeActionsPanel extends StatelessWidget {
  const SellerDisputeActionsPanel({super.key, required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final s = SellerDisputeActions.of(dispute);
    if (!s.isActive) return const SizedBox.shrink();

    final String waitingCopy;
    if (s.awaitingReturnWindow) {
      waitingCopy =
          'Kamu meminta retur. Menunggu pembeli menyetujui atau menolak '
          'permintaan ini.';
    } else if (dispute.returnDeadline != null &&
        dispute.returnTracking == null) {
      waitingCopy =
          'Pembeli sedang mengirim barang retur. Konfirmasi setelah barang '
          'diterima.';
    } else {
      waitingCopy = 'Tunggu respons pembeli pada tawaran yang kamu kirim.';
    }

    return _Stack([
      if (s.returnInTransit) _ConfirmReturnReceived(dispute: dispute),
      if (s.awaitingSellerResponse && !s.returnInTransit)
        _SellerActionSelector(dispute: dispute, partialUsed: s.partialUsed),
      if (s.waitingForBuyer && !s.returnInTransit)
        _Note(title: 'Menunggu pembeli', body: waitingCopy),
      if (s.answersAdminRequest) _AdminEvidenceRequest(dispute: dispute),
      if (s.inAdminReview && !s.answersAdminRequest) const _AdminReviewNote(),
    ]);
  }
}

class _Stack extends StatelessWidget {
  const _Stack(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

// ── Shared plumbing ───────────────────────────────────────────────────────

/// Runs one action and reports it: the server's sentence on failure, [done]
/// on success, then every screen that shows this dispute reloads.
Future<bool> _run(
  BuildContext context,
  WidgetRef ref,
  DisputeModel dispute,
  Future<String?> Function(DisputesRepository repo) action, {
  required String done,
}) async {
  final error = await action(ref.read(disputesRepositoryProvider));
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(error ?? done), persist: false));
  if (error != null) return false;

  ref.invalidate(disputeDetailProvider(dispute.slug));
  ref.invalidate(siblingDisputesProvider(dispute.slug));
  // The order screens read the dispute's status off their own rows.
  if (dispute.role == DisputeRole.buyer) {
    ref.invalidate(ordersProvider);
    ref.invalidate(orderDetailProvider);
    ref.invalidate(orderDisputeProvider);
  } else {
    ref.invalidate(sellerOrdersProvider);
    ref.invalidate(sellerOrderDetailProvider);
  }
  return true;
}

/// Web's action card: an icon, a heading and a line of explanation, with
/// whatever the action needs below.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    this.children = const [],
    this.tint,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  /// Colors the border and icon when the card asks for a decision.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = tint ?? context.mutedForeground;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.06) ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: tint?.withValues(alpha: 0.35) ?? context.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[const SizedBox(height: 12), ...children],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) =>
      _ActionCard(icon: LucideIcons.hourglass, title: title, body: body);
}

class _AdminReviewNote extends StatelessWidget {
  const _AdminReviewNote();

  @override
  Widget build(BuildContext context) => const _ActionCard(
    icon: LucideIcons.shieldCheck,
    title: 'Sedang ditinjau admin',
    body: 'Tunggu keputusan tim pokepedia.id.',
    tint: Color(0xFF3B82F6),
  );
}

/// Two buttons side by side, each showing its own busy state.
class _DecisionButtons extends StatefulWidget {
  const _DecisionButtons({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final Future<void> Function() onPrimary;
  final Future<void> Function() onSecondary;

  @override
  State<_DecisionButtons> createState() => _DecisionButtonsState();
}

class _DecisionButtonsState extends State<_DecisionButtons> {
  /// 0 = primary, 1 = secondary, null = idle.
  int? _busy;

  Future<void> _go(int which) async {
    setState(() => _busy = which);
    try {
      await (which == 0 ? widget.onPrimary() : widget.onSecondary());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy != null;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: locked ? null : () => _go(0),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
            child: Text(_busy == 0 ? 'Memproses...' : widget.primaryLabel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: locked ? null : () => _go(1),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
            child: Text(_busy == 1 ? 'Memproses...' : widget.secondaryLabel),
          ),
        ),
      ],
    );
  }
}

/// A button that asks first — web's button + `ConfirmDialog` pairs.
class _ConfirmedButton extends ConsumerWidget {
  const _ConfirmedButton({
    required this.dispute,
    required this.icon,
    required this.label,
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.action,
    required this.done,
    this.loadingLabel = 'Memproses...',
    this.filled = false,
    this.foreground,
    this.border,
  });

  final DisputeModel dispute;
  final IconData icon;
  final String label;
  final String title;
  final String description;
  final String confirmLabel;
  final String loadingLabel;
  final Future<String?> Function(DisputesRepository repo) action;
  final String done;
  final bool filled;

  /// Outline colors, when the action has a tint of its own.
  final Color? foreground;
  final Color? border;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onPressed() => showConfirmDialog(
      context,
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      loadingLabel: loadingLabel,
      destructive: false,
      onConfirm: () => _run(context, ref, dispute, action, done: done),
    );

    final child = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final iconWidget = Icon(icon, size: 16);
    const size = Size.fromHeight(42);
    return filled
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: child,
            style: ElevatedButton.styleFrom(minimumSize: size),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: child,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              foregroundColor: foreground,
              side: border == null ? null : BorderSide(color: border!),
            ),
          );
  }
}

/// "Minta bantuan admin" — web's `EscalateButton`, used in the page header
/// and inside the seller's action picker.
class DisputeEscalateButton extends StatelessWidget {
  const DisputeEscalateButton({super.key, required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    // Web's `text-blue-700 border-blue-300`, and
    // `dark:text-blue-300 dark:border-blue-800`.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _ConfirmedButton(
      dispute: dispute,
      icon: LucideIcons.shieldAlert,
      label: 'Minta bantuan admin',
      foreground: dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      border: dark ? const Color(0xFF1E40AF) : const Color(0xFF93C5FD),
      title: 'Eskalasi ke admin?',
      description:
          'Admin akan meninjau bukti dari kedua pihak. Tindakan ini tidak bisa '
          'dibatalkan.',
      confirmLabel: 'Eskalasi',
      action: (repo) => repo.escalate(dispute.id),
      done: 'Komplain diteruskan ke admin',
    );
  }
}

// ── Buyer ─────────────────────────────────────────────────────────────────

class _PartialOfferDecision extends ConsumerWidget {
  const _PartialOfferDecision({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> respond(bool accept) => _run(
      context,
      ref,
      dispute,
      (repo) => repo.respondPartialRefund(dispute.id, accept: accept),
      done: accept
          ? 'Refund sebagian diterima. Dana akan masuk ke saldo kamu.'
          : 'Tawaran ditolak. Penjual akan mengajukan opsi lain.',
    );

    return _ActionCard(
      icon: LucideIcons.handCoins,
      tint: context.appColors.primary,
      title:
          'Penjual menawarkan refund '
          '${formatRupiah(dispute.proposedRefundAmount ?? 0)}',
      body:
          'Sisanya diteruskan ke penjual jika kamu menerima. Jika menolak, '
          'penjual akan diminta mengajukan opsi lain.',
      children: [
        _DecisionButtons(
          primaryLabel: 'Terima',
          secondaryLabel: 'Tolak',
          onPrimary: () => respond(true),
          onSecondary: () => respond(false),
        ),
      ],
    );
  }
}

class _ReturnRequestDecision extends ConsumerWidget {
  const _ReturnRequestDecision({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> respond(bool approve) => _run(
      context,
      ref,
      dispute,
      (repo) => repo.answerReturnRequest(dispute.id, approve: approve),
      done: approve
          ? 'Retur disetujui. Kirim barang dan masukkan nomor resi.'
          : 'Permintaan retur ditolak. Penjual akan memilih opsi lain.',
    );

    return _ActionCard(
      icon: LucideIcons.packageSearch,
      tint: context.appColors.primary,
      title: 'Penjual meminta kamu mengembalikan barang',
      body:
          'Setujui jika kamu bersedia meretur. Tolak jika tidak, dan penjual '
          'akan diminta memilih opsi lain.',
      children: [
        _DecisionButtons(
          primaryLabel: 'Setuju Retur',
          secondaryLabel: 'Tolak',
          onPrimary: () => respond(true),
          onSecondary: () => respond(false),
        ),
      ],
    );
  }
}

/// Web's `BuyerSubmitReturnTrackingForm`.
///
/// Web prints the seller's return address here, read with the service role.
/// The app can't read another user's `seller_profiles` row, so it points the
/// buyer at the seller instead of showing nothing.
class _ReturnTrackingForm extends ConsumerStatefulWidget {
  const _ReturnTrackingForm({required this.dispute});

  final DisputeModel dispute;

  @override
  ConsumerState<_ReturnTrackingForm> createState() =>
      _ReturnTrackingFormState();
}

class _ReturnTrackingFormState extends ConsumerState<_ReturnTrackingForm> {
  final _tracking = TextEditingController();
  String? _courier;
  bool _submitting = false;

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tracking = _tracking.text.trim();
    final courier = _courier;
    if (courier == null) {
      _toast('Pilih kurir terlebih dahulu');
      return;
    }
    if (tracking.length < 3) {
      _toast('Nomor resi minimal 3 karakter');
      return;
    }
    setState(() => _submitting = true);
    await _run(
      context,
      ref,
      widget.dispute,
      (repo) => repo.submitReturnTracking(
        widget.dispute.id,
        courier: courier,
        tracking: tracking,
      ),
      done: 'Resi terkirim',
    );
    if (mounted) setState(() => _submitting = false);
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));

  @override
  Widget build(BuildContext context) {
    final couriers = ref.watch(manualCouriersProvider).valueOrNull ?? const [];
    final options = [
      for (final c in couriers)
        if (c.code.isNotEmpty) (value: c.code, label: c.name),
      (value: 'other', label: 'Lainnya'),
    ];

    return _ActionCard(
      icon: LucideIcons.rotateCcw,
      tint: context.appColors.primary,
      title: 'Kirim balik barang dan masukkan resi',
      body:
          'Kirim ke alamat penjual lalu masukkan kurir + nomor resi sebelum '
          'batas waktu. Jika lewat, dana otomatis diteruskan ke penjual.',
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.mutedForeground.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.mapPin,
                size: 14,
                color: context.mutedForeground,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Minta alamat retur ke penjual lewat chat pesanan.',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _courier,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Pilih kurir'),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: _submitting ? null : (v) => setState(() => _courier = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tracking,
          enabled: !_submitting,
          maxLength: 64,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Nomor resi',
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(_submitting ? 'Mengirim...' : 'Kirim Resi'),
        ),
      ],
    );
  }
}

class _WithdrawButton extends StatelessWidget {
  const _WithdrawButton({required this.dispute, required this.itemSlug});

  final DisputeModel dispute;
  final String itemSlug;

  @override
  Widget build(BuildContext context) => _ConfirmedButton(
    dispute: dispute,
    icon: LucideIcons.undo2,
    label: 'Batalkan Komplain',
    title: 'Batalkan komplain?',
    description: 'Komplain akan ditutup dan pesanan dilanjutkan seperti biasa.',
    confirmLabel: 'Batalkan Komplain',
    loadingLabel: 'Membatalkan...',
    action: (repo) => repo.withdraw(itemSlug),
    done: 'Komplain dibatalkan',
  );
}

class _AdminEvidenceRequest extends StatelessWidget {
  const _AdminEvidenceRequest({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final due = dispute.evidenceRequestDueAt;
    return DisputeResponseForm(
      dispute: dispute,
      title: 'Admin Pokepedia meminta bukti',
      description:
          'Baca pesan admin di Diskusi & bukti, lalu kirim jawaban dan foto '
          'pendukung.${due == null ? '' : ' Kirim sebelum ${formatDeadlineId(due)}.'}',
    );
  }
}

// ── Seller ────────────────────────────────────────────────────────────────

class _ConfirmReturnReceived extends StatelessWidget {
  const _ConfirmReturnReceived({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) => _ActionCard(
    icon: LucideIcons.packageCheck,
    tint: context.appSemantic.success,
    title: 'Barang retur sudah tiba?',
    body:
        'Resi: ${(dispute.returnCourier ?? '').toUpperCase()} '
        '${dispute.returnTracking ?? ''}\n'
        'Konfirmasi setelah kamu menerima dan memeriksa barang. Dana akan '
        'direfund ke pembeli.',
    children: [
      _ConfirmedButton(
        dispute: dispute,
        icon: LucideIcons.packageCheck,
        label: 'Konfirmasi Diterima',
        title: 'Konfirmasi barang retur diterima?',
        description:
            'Setelah konfirmasi, dana barang akan direfund ke pembeli (ongkir '
            'tidak termasuk) dan komplain selesai.',
        confirmLabel: 'Konfirmasi',
        loadingLabel: 'Mengonfirmasi...',
        filled: true,
        action: (repo) => repo.confirmReturnReceived(dispute.id),
        done: 'Konfirmasi diterima',
      ),
    ],
  );
}

/// Web's `SellerActionSelector`: pick a way to settle, then act on it.
class _SellerActionSelector extends StatefulWidget {
  const _SellerActionSelector({
    required this.dispute,
    required this.partialUsed,
  });

  final DisputeModel dispute;
  final bool partialUsed;

  @override
  State<_SellerActionSelector> createState() => _SellerActionSelectorState();
}

class _SellerActionSelectorState extends State<_SellerActionSelector> {
  SellerDisputeAction? _picked;

  List<SellerDisputeAction> get _options => sellerDisputeOptions(
    widget.dispute.reasonCategory,
    partialUsed: widget.partialUsed,
  );

  /// The pick, unless a reload took it off the list — then the first option.
  SellerDisputeAction get _action {
    final options = _options;
    return options.contains(_picked) ? _picked! : options.first;
  }

  static const _icons = {
    SellerDisputeAction.message: LucideIcons.messageSquare,
    SellerDisputeAction.fullRefund: LucideIcons.circleDollarSign,
    SellerDisputeAction.partialRefund: LucideIcons.handCoins,
    SellerDisputeAction.requestReturn: LucideIcons.rotateCcw,
    SellerDisputeAction.refundShortfall: LucideIcons.packageMinus,
    SellerDisputeAction.escalate: LucideIcons.shieldAlert,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final d = widget.dispute;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pilih tindakan',
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 10),
          for (final option in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _OptionTile(
                icon: _icons[option]!,
                label: option.label,
                selected: option == _action,
                onTap: () => setState(() => _picked = option),
              ),
            ),
          const SizedBox(height: 8),
          switch (_action) {
            SellerDisputeAction.message => DisputeResponseForm(
              dispute: d,
              embedded: true,
            ),
            SellerDisputeAction.fullRefund => _ConfirmedButton(
              dispute: d,
              icon: LucideIcons.circleDollarSign,
              label: 'Refund penuh',
              title: 'Refund penuh ke pembeli?',
              description:
                  'Dana barang ${formatRupiah(d.escrowAmount)} akan '
                  'dikembalikan ke pembeli (ongkir tidak termasuk). Pesanan '
                  'dibatalkan. Tindakan ini tidak bisa dibatalkan.',
              confirmLabel: 'Refund Penuh',
              action: (repo) => repo.fullRefund(d.id),
              done: 'Refund penuh terkirim ke pembeli',
            ),
            SellerDisputeAction.partialRefund => _PartialRefundForm(dispute: d),
            SellerDisputeAction.requestReturn => _RequestReturn(dispute: d),
            SellerDisputeAction.refundShortfall => _ShortfallRefund(dispute: d),
            SellerDisputeAction.escalate => DisputeEscalateButton(dispute: d),
          },
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.05) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 16,
              color: selected ? colors.primary : context.mutedForeground,
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 16, color: context.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: AppTypography.bodySm(colors.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialRefundForm extends ConsumerStatefulWidget {
  const _PartialRefundForm({required this.dispute});

  final DisputeModel dispute;

  @override
  ConsumerState<_PartialRefundForm> createState() => _PartialRefundFormState();
}

class _PartialRefundFormState extends ConsumerState<_PartialRefundForm> {
  final _amount = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));

  @override
  Widget build(BuildContext context) {
    final escrow = widget.dispute.escrowAmount;
    final value = _value;
    final valid = value != null && value > 0 && value < escrow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Kurang dari ${formatRupiah(escrow)}. Sisanya diteruskan ke kamu '
          'setelah pembeli menerima tawaran.',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          enabled: !_submitting,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            const PriceInputFormatter(),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Masukkan nominal',
            prefixText: 'Rp ',
            errorText: value != null && !valid
                ? 'Nominal harus 1 - ${formatRupiah(escrow - 1)}'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: !valid || _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  await _run(
                    context,
                    ref,
                    widget.dispute,
                    (repo) =>
                        repo.proposePartialRefund(widget.dispute.id, value),
                    done: 'Tawaran refund dikirim ke pembeli',
                  );
                  if (mounted) setState(() => _submitting = false);
                },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(_submitting ? 'Mengirim...' : 'Tawarkan'),
        ),
      ],
    );
  }
}

class _RequestReturn extends StatelessWidget {
  const _RequestReturn({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Pembeli wajib mengirim resi dalam 3 hari. Jika tidak, dana '
        'diteruskan ke kamu otomatis.',
        style: AppTypography.caption(context.mutedForeground),
      ),
      const SizedBox(height: 8),
      _ConfirmedButton(
        dispute: dispute,
        icon: LucideIcons.rotateCcw,
        label: 'Minta Retur',
        title: 'Minta retur dari pembeli?',
        description:
            'Pembeli punya 3 hari untuk mengirim resi. Setelah barang '
            'diterima dan kamu konfirmasi, dana akan direfund ke pembeli.',
        confirmLabel: 'Kirim permintaan',
        loadingLabel: 'Mengirim...',
        action: (repo) => repo.requestReturn(dispute.id),
        done: 'Permintaan retur dikirim ke pembeli',
      ),
    ],
  );
}

class _ShortfallRefund extends StatelessWidget {
  const _ShortfallRefund({required this.dispute});

  final DisputeModel dispute;

  @override
  Widget build(BuildContext context) {
    final short = dispute.shortQuantity ?? 0;
    final matched = dispute.item?.matchedQuantity ?? 1;
    final caption = AppTypography.caption(context.mutedForeground);
    if (short <= 0) {
      return Text(
        'Jumlah barang kurang tidak tercatat. Gunakan "Minta bantuan admin" '
        'agar admin menetapkan refund yang tepat.',
        style: caption,
      );
    }
    final amount = formatRupiah(shortfallRefundAmount(dispute));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Refund $amount untuk $short unit yang kurang dari total $matched '
          'unit.',
          style: caption,
        ),
        const SizedBox(height: 8),
        _ConfirmedButton(
          dispute: dispute,
          icon: LucideIcons.packageMinus,
          label: 'Refund barang yang kurang',
          title: 'Refund barang yang kurang?',
          description:
              'Dana $amount akan dikembalikan ke pembeli untuk $short unit '
              'yang tidak terkirim. Sisa dana dilepas ke kamu. Tindakan ini '
              'tidak bisa dibatalkan.',
          confirmLabel: 'Kirim Refund',
          loadingLabel: 'Mengirim...',
          action: (repo) => repo.refundShortfall(dispute.id),
          done: 'Refund barang yang kurang terkirim ke pembeli',
        ),
      ],
    );
  }
}

// ── Either side ───────────────────────────────────────────────────────────

/// Web's `DisputeResponseForm`: a statement and up to four photos, posted
/// to the dispute's discussion.
class DisputeResponseForm extends ConsumerStatefulWidget {
  const DisputeResponseForm({
    super.key,
    required this.dispute,
    this.title = 'Respon komplain',
    this.description =
        'Jelaskan kronologi dan lampirkan bukti (foto paket, resi, '
        'percakapan).',
    this.embedded = false,
  });

  final DisputeModel dispute;
  final String title;
  final String description;

  /// Inside the seller's action selector, which already draws the card.
  final bool embedded;

  @override
  ConsumerState<DisputeResponseForm> createState() =>
      _DisputeResponseFormState();
}

class _DisputeResponseFormState extends ConsumerState<DisputeResponseForm> {
  final _statement = TextEditingController();
  final _photos = <DisputeEvidencePhoto>[];
  bool _submitting = false;

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));

  Future<void> _addPhoto() async {
    if (_photos.length >= disputeMaxPhotos) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final extension = picked.name.split('.').last.toLowerCase();
    final contentType = disputePhotoMimeByExtension[extension];
    if (contentType == null) {
      _toast('Format harus JPG, PNG, atau WebP');
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > disputeMaxPhotoBytes) {
      _toast('Ukuran maksimal 5MB');
      return;
    }
    setState(
      () => _photos.add(
        DisputeEvidencePhoto(
          bytes: bytes,
          contentType: contentType,
          extension: extension == 'jpeg' ? 'jpg' : extension,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final statement = _statement.text.trim();
    if (statement.isEmpty) return;
    setState(() => _submitting = true);
    final sent = await _run(
      context,
      ref,
      widget.dispute,
      (repo) => repo.respond(
        widget.dispute.settlementSlug,
        statement: statement,
        photos: List.of(_photos),
      ),
      done: 'Respon terkirim',
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (sent) {
        _statement.clear();
        _photos.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Text(
            widget.title,
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            widget.description,
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _statement,
          enabled: !_submitting,
          minLines: 4,
          maxLines: 8,
          maxLength: disputeMaxDetail,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText:
                'Contoh: Paket sudah saya serahkan ke kurir JNE pada '
                'tanggal...',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Foto bukti (${_photos.length}/$disputeMaxPhotos)',
          style: AppTypography.captionSemibold(context.mutedForeground),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _photos.length; i++)
              _PhotoThumb(
                photo: _photos[i],
                onRemove: _submitting
                    ? null
                    : () => setState(() => _photos.removeAt(i)),
              ),
            if (_photos.length < disputeMaxPhotos)
              InkWell(
                onTap: _submitting ? null : _addPhoto,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Icon(
                    LucideIcons.camera,
                    size: 20,
                    color: context.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _submitting || _statement.text.trim().isEmpty
              ? null
              : _submit,
          icon: const Icon(LucideIcons.send, size: 16),
          label: Text(_submitting ? 'Mengirim...' : 'Kirim respon'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ],
    );

    if (widget.embedded) return form;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: form,
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.onRemove});

  final DisputeEvidencePhoto photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.memory(photo.bytes, fit: BoxFit.cover),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    size: 12,
                    color: Colors.white,
                    semanticLabel: 'Hapus foto',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
