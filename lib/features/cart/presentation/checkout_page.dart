import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/routes.dart';
import '../../../core/network/pokepedia_api.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import 'widgets/empty_cart_card.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../account/presentation/widgets/address_form_sheet.dart';
import '../../account/repository/models/address_model.dart';
import '../../account/usecase/address_notifier.dart';
import '../../wallet/usecase/wallet_notifier.dart';
import '../repository/models/cart_item.dart';
import '../repository/models/checkout_models.dart';
import '../usecase/cart_notifier.dart';
import '../usecase/cart_selection.dart';
import '../../orders/usecase/orders_notifier.dart';
import '../usecase/checkout_notifier.dart';
import 'checkout/buyer_note_box.dart';
import 'checkout/order_summary.dart';
import 'checkout/payment_method_picker.dart';
import 'checkout/payment_section.dart';
import 'checkout/seller_group_card.dart';
import 'checkout_status_page.dart';
import 'payment_webview_page.dart';

/// Ports `features/checkout`'s buyer flow for WTS (ask) listings natively:
/// the order grouped per seller, delivery address, live courier quotes,
/// shipping insurance, promo code, buyer note, payment choice and totals.
///
/// Only the last screen isn't native, by design — a card or VA payment is
/// completed on Xendit's own hosted invoice page, which is the gateway's
/// PCI surface and not something to reimplement. `/api/cart/checkout`
/// returns that URL and this page opens it.
///
/// The two server calls behind this (Biteship quotes, Xendit invoice) stay
/// on pokepedia.id: they need `BITESHIP_API_KEY` / `XENDIT_SECRET_KEY` and
/// `service_role`, none of which belong in a shipped app. The app
/// authenticates to them with its own Supabase session, which
/// `getRequestAuth` accepts. If those routes can't be reached the buyer
/// stays here and is told so — checkout is never handed off to the web
/// version, which would run pricing and address selection a second time
/// against a session this page can't see, with both racing over one cart.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _couponInput = TextEditingController();

  @override
  void dispose() {
    _couponInput.dispose();
    super.dispose();
  }

  /// Falls back to the primary address until the buyer picks another, then
  /// pushes it into the notifier so shipping is quoted against it.
  AddressModel? _syncAddress(List<AddressModel> addresses) {
    final state = ref.read(checkoutProvider);
    final chosen = state.address;
    if (chosen != null) {
      for (final address in addresses) {
        if (address.id == chosen.id) return address;
      }
    }
    if (addresses.isEmpty) return null;
    final fallback = addresses.firstWhere(
      (a) => a.isPrimary,
      orElse: () => addresses.first,
    );
    // Deferred: this runs during build, and selecting kicks off a fetch.
    Future.microtask(
      () => ref.read(checkoutProvider.notifier).selectAddress(fallback),
    );
    return fallback;
  }

  Future<void> _pickAddress(
    List<AddressModel> addresses,
    int? selectedId,
  ) async {
    final picked = await showModalBottomSheet<AddressModel>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Alamat pengiriman',
                style: AppTypography.h3(context.appColors.onSurface),
              ),
            ),
            for (final address in addresses)
              ListTile(
                title: Text(
                  '${address.label} · ${address.contactName}',
                  style: AppTypography.bodySmSemibold(
                    context.appColors.onSurface,
                  ),
                ),
                subtitle: Text(
                  address.areaLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
                trailing: address.id == selectedId
                    ? Icon(LucideIcons.check, color: context.appColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(address),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  showAddressFormSheet(context);
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Tambah alamat baru'),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      ref.read(checkoutProvider.notifier).selectAddress(picked);
    }
  }

  /// Validates locally, submits, then opens the gateway's page.
  /// True from the moment the payment page is pushed until it closes.
  bool _paying = false;

  Future<void> _pay() async {
    final notifier = ref.read(checkoutProvider.notifier);

    final problems = await ref
        .read(cartRepositoryProvider)
        .validate(only: ref.read(cartSelectionProvider));
    if (!mounted) return;
    if (problems.isNotEmpty) {
      await ref.read(cartProvider.notifier).refresh();
      if (!mounted) return;
      _toast(problems.first);
      return;
    }

    try {
      final result = await notifier.submit();
      if (!mounted) return;

      final invoiceUrl = result.invoiceUrl;
      final externalId = result.externalId;
      // Read before anything mutates the cart: `selectedCartItemsProvider`
      // is derived from it, so it empties the moment the lines are removed.
      final checkedOutItemIds = [
        for (final item in ref.read(selectedCartItemsProvider)) item.cartItemId,
      ];
      final method = ref.read(checkoutProvider).paymentMethod;
      final channel = ref.read(checkoutProvider).paymentChannel;

      // Paying from the wallet is settled by the time `submit` returns, so
      // there's nothing to show and nothing to poll.
      if (method == PaymentMethod.wallet) {
        await ref.read(cartProvider.notifier).refresh();
        if (mounted) context.goHomeThen(Routes.orders);
        return;
      }

      // Every channel goes to Xendit's hosted invoice — QRIS included.
      // That is the documented flow (§5 of the bearer-auth handoff: mobile
      // opens a WebView on `invoiceUrl` and nothing else), and the Invoice
      // API exposes no QR payload for the app to draw itself.
      if (invoiceUrl != null) {
        // Push first, then clear — deliberately in that order, and
        // deliberately not awaiting the push before clearing.
        //
        // Clearing has to happen now rather than on return: payment often
        // finishes in a banking app with this page long gone, and a cart
        // still holding what was just bought invites a double purchase. But
        // emptying the cart rebuilds this page into its empty state, which
        // flashed behind the route transition. Starting the push first puts
        // the WebView over the top before that rebuild lands.
        setState(() => _paying = true);
        final closed = Navigator.of(context).push(
          MaterialPageRoute<PaymentOutcome>(
            builder: (_) => PaymentWebViewPage(invoiceUrl: invoiceUrl),
          ),
        );

        await ref.read(cartProvider.notifier).removeItems(checkedOutItemIds);
        // The checkout now exists as an unpaid cart, which is what Pesanan
        // shows under Belum Bayar.
        ref.invalidate(myPendingCheckoutsProvider);

        await closed;
        if (mounted) setState(() => _paying = false);
      } else if (result.redirect != null) {
        // `/api/cart/checkout` only returns a bare `redirect` from its
        // wallet branch, so reaching this on a card payment means the
        // response didn't come from where we think. Report the target
        // rather than asserting the order was processed.
        await ref.read(cartProvider.notifier).refresh();
        if (mounted) {
          _toast(
            'Server mengarahkan ke ${result.redirect} '
            '(channel: ${channel?.code ?? "-"}, '
            'ref: ${externalId ?? "-"}).',
          );
        }
        return;
      } else {
        // No QR to draw and no page to open. Name what came back, because
        // "not available" alone is undiagnosable — this is the branch that
        // means the checkout response wasn't the shape we expect.
        _toast(
          'Halaman pembayaran tidak tersedia '
          '(channel: ${channel?.code ?? "-"}, '
          'ref: ${externalId ?? "-"}).',
        );
        return;
      }
      if (!mounted) return;

      // Deliberately regardless of how the payment page closed. Returning
      // isn't proof of payment, and dismissing isn't proof it didn't
      // happen — a VA transfer is often paid in a banking app with the
      // page long gone. Only our own backend knows, so go ask it.
      if (externalId == null) {
        // No id to poll with, so there's nothing to confirm against — the
        // order still exists server-side. Named rather than silent: landing
        // on Pesanan with no explanation looks like the payment was skipped.
        await ref.read(cartProvider.notifier).refresh();
        if (mounted) {
          _toast(
            'Checkout tidak mengembalikan nomor referensi. Cek status di '
            'Pesanan.',
          );
          // context.go(Routes.orders);
        }
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckoutStatusPage(
            externalId: externalId,
            droppedItems: result.droppedItems,
          ),
        ),
      );
      if (!mounted) return;
      await ref.read(cartProvider.notifier).refresh();
    } on ApiUnreachableException catch (e) {
      // Reported and left at that. Handing the buyer the web checkout
      // instead would restart pricing and address selection in a second
      // place, against a session the app can't see the state of — two
      // checkouts racing over the same cart. Staying put means retrying is
      // one tap, on the numbers already on screen.
      if (!mounted) return;
      _toast(e.message);
    } on ApiSessionExpiredException catch (e) {
      // The one auth failure worth interrupting for: the token could not be
      // refreshed, so nothing the buyer does here will work until they sign
      // in again. Every other 401 was already retried transparently.
      if (!mounted) return;
      _toast(e.message);
      context.push(Routes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          persist: false,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Only what was ticked in the cart. `CheckoutNotifier` already prices
    // and submits the selection, so reading the whole cart here showed a
    // buyer two lines while charging them for one.
    final items = ref.watch(selectedCartItemsProvider);
    final cartIsEmpty = ref.watch(cartProvider).isEmpty;
    final state = ref.watch(checkoutProvider);
    final notifier = ref.watch(checkoutProvider.notifier);
    final addresses = ref.watch(addressesProvider).valueOrNull ?? const [];
    final address = _syncAddress(addresses);

    // Wallet payment is gated on the real balance, so keep it in sync.
    ref.listen(walletBalanceProvider, (_, next) {
      final balance = next.valueOrNull;
      if (balance != null) notifier.setWalletBalance(balance);
    });

    final groups = _groupBySeller(items);
    final totals = notifier.totals;
    final blockedReason = notifier.blockedReason;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        // While the payment page is up, this one is only ever a backdrop.
        // Clearing the cart empties the selection, which would otherwise
        // rebuild this into "Keranjang kosong" and flash it through the
        // route transition — a page the buyer never asked to see.
        child: _paying
            ? const PikachuLoader()
            // An empty cart and an empty selection are different problems
            // with different exits, so they are separate branches rather
            // than one empty state with swapped copy.
            //
            // Cart empty is checked first: with nothing in the cart there is
            // nothing to go back and select, so "Kembali ke Keranjang" would
            // be a dead end.
            : cartIsEmpty
            ? const EmptyCartCard()
            : items.isEmpty
            ? EmptyState(
                icon: LucideIcons.square,
                title: 'Belum ada kartu yang dipilih',
                description: 'Pilih kartu di keranjang untuk dilanjutkan.',
                action: ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Kembali ke Keranjang'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Checkout',
                    style: AppTypography.h2(context.appColors.onSurface),
                  ),
                  const SizedBox(height: 12),

                  _AddressSection(
                    address: address,
                    onTap: () => addresses.isEmpty
                        ? showAddressFormSheet(context)
                        : _pickAddress(addresses, address?.id),
                  ),

                  if (state.contextError != null) ...[
                    const SizedBox(height: 12),
                    _ServerUnreachableNotice(
                      message: state.contextError!,
                      onRetry: notifier.loadContext,
                    ),
                  ],

                  const SizedBox(height: 12),
                  for (final entry in groups.entries) ...[
                    SellerGroupCard(
                      items: entry.value,
                      courierOptions:
                          state.shippingBySeller[entry.key]?.options ??
                          const [],
                      selectedCourier:
                          state.shippingBySeller[entry.key]?.selected,
                      onSelectCourier: (option) =>
                          notifier.selectCourier(entry.key, option),
                      insuranceEnabled:
                          state.insuranceBySeller[entry.key] ?? false,
                      onToggleInsurance: (next) =>
                          notifier.toggleInsurance(entry.key, next),
                      hasAddress: address != null,
                      ratesLoading:
                          state.contextLoading ||
                          (state.shippingBySeller[entry.key]?.loading ?? false),
                      ratesError: state.shippingBySeller[entry.key]?.error,
                      onRetryRates: () =>
                          notifier.fetchRatesForSeller(entry.key),
                    ),
                    const SizedBox(height: 12),
                  ],

                  BuyerNoteBox(
                    value: state.buyerNote,
                    onChanged: notifier.setBuyerNote,
                  ),
                  const SizedBox(height: 12),

                  PaymentSection(
                    grandTotalBeforeFee: totals.grandTotalBeforeFee,
                    paymentMethod: state.paymentMethod,
                    paymentChannel: state.paymentChannel,
                    walletBalance: state.walletBalance,
                    onPick: (pick) => switch (pick) {
                      XenditPick(:final channel) => notifier.selectXendit(
                        channel,
                      ),
                      WalletPick() => notifier.selectWallet(),
                    },
                  ),
                  const SizedBox(height: 12),

                  OrderSummary(
                    itemsSubtotal: notifier.itemsSubtotal,
                    shippingTotal: notifier.shippingTotal,
                    insuranceTotal: notifier.insuranceTotal,
                    paymentMethod: state.paymentMethod,
                    hasChannel: state.paymentChannel != null,
                    totals: totals,
                    appliedCoupon: state.coupon,
                    couponInput: _couponInput.text,
                    onCouponInputChanged: (value) =>
                        setState(() => _couponInput.text = value),
                    couponLoading: state.couponLoading,
                    couponApplyDisabled:
                        _couponInput.text.trim().isEmpty ||
                        state.paymentChannel == null ||
                        state.paymentMethod == PaymentMethod.wallet,
                    onApplyCoupon: () =>
                        notifier.applyCoupon(_couponInput.text),
                    onRemoveCoupon: notifier.removeCoupon,
                    submitting: state.submitting,
                    payDisabled: blockedReason != null,
                    onCheckout: _pay,
                  ),

                  if (state.couponError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.couponError!,
                      style: AppTypography.caption(context.appColors.error),
                    ),
                  ],
                  if (blockedReason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      blockedReason,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// Groups by `listings.user_id`, as the web does — a seller can have more
  /// than one store slug, and the checkout payload is keyed by seller id.
  Map<String, List<CartItem>> _groupBySeller(List<CartItem> items) {
    final map = <String, List<CartItem>>{};
    for (final item in items) {
      (map[item.listing.sellerId] ??= []).add(item);
    }
    return map;
  }
}

/// Shown when the seller origins or courier quotes can't be fetched. Both
/// need the server, so the honest options are retry or finish on the web.
class _ServerUnreachableNotice extends StatelessWidget {
  const _ServerUnreachableNotice({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppTypography.bodySm(colors.onSurface)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({required this.address, required this.onTap});

  final AddressModel? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final address = this.address;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(
            color: address == null
                ? colors.error.withValues(alpha: 0.5)
                : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.mapPin, size: 20, color: context.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: address == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Belum ada alamat pengiriman',
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        Text(
                          'Tambahkan alamat untuk melanjutkan',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${address.label} · ${address.contactName}',
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        Text(
                          address.contactPhone,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address.fullAddress,
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                        Text(
                          address.areaLine,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
            ),
            Text(
              address == null ? 'Tambah' : 'Ubah',
              style: AppTypography.captionSemibold(colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
