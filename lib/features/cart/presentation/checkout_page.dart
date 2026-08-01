import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../repository/checkout_dummy_data.dart';
import '../repository/checkout_pricing.dart';
import '../repository/models/cart_item.dart';
import '../repository/models/checkout_models.dart';
import '../usecase/cart_notifier.dart';
import 'checkout/buyer_note_box.dart';
import 'checkout/checkout_address_picker.dart';
import 'checkout/order_summary.dart';
import 'checkout/payment_method_picker.dart';
import 'checkout/payment_section.dart';
import 'checkout/seller_group_card.dart';

/// Ports `features/checkout/ui/CheckoutClient.tsx` — address, per-seller
/// shipping/insurance, buyer note, payment method, and order summary, all
/// backed by dummy data ([CheckoutDummyData]) while this pass only ports
/// the UI.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CalcResult {
  const _CalcResult({
    required this.groups,
    required this.itemsSubtotal,
    required this.shippingTotal,
    required this.insuranceTotal,
    required this.totals,
  });

  final Map<String, List<CartItem>> groups;
  final int itemsSubtotal;
  final int shippingTotal;
  final int insuranceTotal;
  final CheckoutTotals totals;
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  CheckoutAddress? _selectedAddress;
  String _buyerNote = '';
  final Map<String, CourierOption?> _selectedCourier = {};
  final Map<String, bool> _insuranceEnabled = {};
  PaymentMethod _paymentMethod = PaymentMethod.xendit;
  PaymentChannel? _paymentChannel;
  String _couponInput = '';
  AppliedCoupon? _appliedCoupon;
  bool _couponLoading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedAddress = CheckoutDummyData.addresses.firstWhere(
      (a) => a.isPrimary,
      orElse: () => CheckoutDummyData.addresses.first,
    );
    _reconcilePayment(ref.read(cartProvider));
  }

  _CalcResult _calc(List<CartItem> items) {
    final groups = <String, List<CartItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.listing.storeSlug, () => []).add(item);
    }
    final itemsSubtotal = items.fold(0, (sum, item) => sum + item.subtotal);
    var shippingTotal = 0;
    var insuranceTotal = 0;
    for (final sellerId in groups.keys) {
      final courier = _selectedCourier[sellerId];
      if (courier == null) continue;
      shippingTotal += courier.cost;
      final insured = _insuranceEnabled[sellerId] ?? false;
      if (insured && courier.insuranceAvailable) {
        insuranceTotal += courier.insuranceFee;
      }
    }
    final totals = computeCheckoutTotals(
      itemsSubtotal: itemsSubtotal,
      shippingTotal: shippingTotal,
      insuranceTotal: insuranceTotal,
      paymentMethod: _paymentMethod,
      paymentChannel: _paymentChannel,
      appliedCoupon: _appliedCoupon,
    );
    return _CalcResult(
      groups: groups,
      itemsSubtotal: itemsSubtotal,
      shippingTotal: shippingTotal,
      insuranceTotal: insuranceTotal,
      totals: totals,
    );
  }

  /// Mirrors `usePayment`'s two effects: drop a channel that's no longer
  /// allowed for the current total, then auto-pick the first allowed one.
  void _reconcilePayment(List<CartItem> items) {
    if (_paymentMethod == PaymentMethod.wallet) return;
    final total = _calc(items).totals.grandTotalBeforeFee;
    final allowed = availablePaymentChannels(total);
    if (_paymentChannel != null && !allowed.contains(_paymentChannel)) {
      _paymentChannel = null;
    }
    if (_paymentChannel == null && total > 0 && allowed.isNotEmpty) {
      _paymentChannel = allowed.first;
    }
  }

  void _selectCourier(String sellerId, CourierOption option, int sellerSubtotal) {
    setState(() {
      _selectedCourier[sellerId] = option;
      if (!option.insuranceAvailable) {
        _insuranceEnabled[sellerId] = false;
      } else if (isInsuranceMandatory(sellerSubtotal)) {
        _insuranceEnabled[sellerId] = true;
      }
      _reconcilePayment(ref.read(cartProvider));
    });
  }

  void _toggleInsurance(String sellerId, bool next, int sellerSubtotal) {
    if (isInsuranceMandatory(sellerSubtotal) && !next) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Asuransi wajib untuk pesanan di atas '
            '${formatRupiah(insuranceMandatoryThresholdIdr)}',
          ),
        ),
      );
      return;
    }
    setState(() {
      _insuranceEnabled[sellerId] = next;
      _reconcilePayment(ref.read(cartProvider));
    });
  }

  void _onPaymentPick(PaymentPick pick) {
    setState(() {
      switch (pick) {
        case XenditPick(:final channel):
          _paymentMethod = PaymentMethod.xendit;
          _paymentChannel = channel;
        case WalletPick():
          _paymentMethod = PaymentMethod.wallet;
          _paymentChannel = null;
      }
    });
  }

  Future<void> _applyCoupon() async {
    final code = _couponInput.trim();
    if (code.isEmpty) {
      _showSnack('Masukkan kode promo');
      return;
    }
    if (_paymentMethod == PaymentMethod.wallet) {
      _showSnack('Promo tidak berlaku untuk pembayaran saldo');
      return;
    }
    if (_paymentChannel == null) {
      _showSnack('Pilih metode pembayaran dulu');
      return;
    }
    setState(() => _couponLoading = true);
    await Future.delayed(const Duration(milliseconds: 400));
    final gatewayFee = _calc(ref.read(cartProvider)).totals.gatewayFee;
    final result = CheckoutDummyData.applyCoupon(code, gatewayFee);
    if (!mounted) return;
    setState(() {
      _couponLoading = false;
      if (result.ok) {
        _appliedCoupon = result.coupon;
        _couponInput = '';
      }
    });
    _showSnack(result.ok ? 'Promo diterapkan' : result.message!);
  }

  void _removeCoupon() {
    setState(() {
      _appliedCoupon = null;
      _couponInput = '';
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleCheckout(_CalcResult calc, bool payDisabled) async {
    if (_submitting || payDisabled) return;
    final items = ref.read(cartProvider);
    final itemCount = items.length;
    final total = calc.totals.grandTotal;

    if (_paymentMethod == PaymentMethod.wallet) {
      var confirmed = false;
      await showConfirmDialog(
        context,
        title: 'Lanjutkan dengan saldo?',
        description:
            'Saldo sebesar ${formatRupiah(calc.totals.grandTotalBeforeFee)} '
            'akan langsung dipotong dari dompet kamu.',
        confirmLabel: 'Lanjutkan',
        loadingLabel: 'Memproses...',
        destructive: false,
        onConfirm: () async {
          confirmed = true;
          await Future.delayed(const Duration(milliseconds: 700));
        },
      );
      if (!confirmed) return;
    } else {
      setState(() => _submitting = true);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!mounted) return;
    ref.read(cartProvider.notifier).clear();
    setState(() => _submitting = false);
    context.push(
      Routes.checkoutSuccess,
      extra: {'itemCount': itemCount, 'total': total},
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final calc = _calc(items);
    final groups = calc.groups;
    final hasAddress = _selectedAddress != null;

    final payDisabled =
        items.isEmpty ||
        !hasAddress ||
        groups.keys.any((id) => _selectedCourier[id] == null) ||
        (_paymentMethod == PaymentMethod.xendit && _paymentChannel == null) ||
        (_paymentMethod == PaymentMethod.wallet &&
            CheckoutDummyData.walletBalance < calc.totals.grandTotalBeforeFee);

    final couponApplyDisabled =
        _couponInput.trim().isEmpty ||
        _paymentChannel == null ||
        _paymentMethod == PaymentMethod.wallet;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        top: false,
        child: items.isEmpty
            ? const EmptyState(
                icon: Icons.shopping_cart_outlined,
                title: 'Keranjang kosong',
                description: 'Yuk cari kartu incaranmu di Market.',
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CheckoutAddressPicker(
                    selected: _selectedAddress,
                    onSelect: (address) =>
                        setState(() => _selectedAddress = address),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in groups.entries) ...[
                    SellerGroupCard(
                      items: entry.value,
                      courierOptions: CheckoutDummyData.courierOptionsFor(
                        entry.key,
                      ),
                      selectedCourier: _selectedCourier[entry.key],
                      hasAddress: hasAddress,
                      onSelectCourier: (opt) => _selectCourier(
                        entry.key,
                        opt,
                        entry.value.fold(0, (s, i) => s + i.subtotal),
                      ),
                      insuranceEnabled: _insuranceEnabled[entry.key] ?? false,
                      onToggleInsurance: (next) => _toggleInsurance(
                        entry.key,
                        next,
                        entry.value.fold(0, (s, i) => s + i.subtotal),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  BuyerNoteBox(
                    value: _buyerNote,
                    onChanged: (v) => _buyerNote = v,
                  ),
                  const SizedBox(height: 12),
                  PaymentSection(
                    grandTotalBeforeFee: calc.totals.grandTotalBeforeFee,
                    paymentMethod: _paymentMethod,
                    paymentChannel: _paymentChannel,
                    walletBalance: CheckoutDummyData.walletBalance,
                    onPick: _onPaymentPick,
                  ),
                  const SizedBox(height: 12),
                  OrderSummary(
                    itemsSubtotal: calc.itemsSubtotal,
                    shippingTotal: calc.shippingTotal,
                    insuranceTotal: calc.insuranceTotal,
                    paymentMethod: _paymentMethod,
                    hasChannel: _paymentChannel != null,
                    totals: calc.totals,
                    appliedCoupon: _appliedCoupon,
                    couponInput: _couponInput,
                    onCouponInputChanged: (v) =>
                        setState(() => _couponInput = v),
                    couponLoading: _couponLoading,
                    couponApplyDisabled: couponApplyDisabled,
                    onApplyCoupon: _applyCoupon,
                    onRemoveCoupon: _removeCoupon,
                    submitting: _submitting,
                    payDisabled: payDisabled,
                    onCheckout: () => _handleCheckout(calc, payDisabled),
                  ),
                ],
              ),
      ),
    );
  }
}
