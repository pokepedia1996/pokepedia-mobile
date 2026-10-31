import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/orders/presentation/dispute_detail_page.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/dispute_model.dart';
import 'package:pokepedia_mobile/features/orders/usecase/orders_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/shipment_repository.dart';

/// The dispute page draws the right panel for each side and state.
DisputeModel _dispute(
  DisputeRole role, {
  String status = 'opened',
  int? proposed,
}) => DisputeModel.fromRow({
  'id': 7,
  'slug': 'dsp-261028-abcde',
  'current_status': status,
  'reason_category': 'damaged',
  'reason': 'Sudut kartu tertekuk',
  'proposed_refund_amount': proposed,
  'opened_at': '2026-10-20T10:00:00Z',
  'response_deadline_at': DateTime.now()
      .add(const Duration(days: 2))
      .toUtc()
      .toIso8601String(),
  'settlements': {
    'slug': 'b1c2d3e4-0000-4000-8000-000000000000',
    'escrow_amount': 300000,
    'condition': 'NM',
    'order_items': {
      'slug': 'item-1',
      'order_number': 'pk-1-a',
      'matched_quantity': 1,
      'cards': {'name_id': 'Pikachu ex'},
    },
  },
  'dispute_events': [
    {
      'event_type': 'opened',
      'actor_role': 'buyer',
      'created_at': '2026-10-20T10:00:00Z',
    },
  ],
  'dispute_evidence': [
    {
      'id': 1,
      'submitted_by_role': 'buyer',
      'evidence_type': 'statement',
      'body': 'Kartu datang dalam keadaan tertekuk',
      'submitted_at': '2026-10-20T10:00:00Z',
    },
  ],
}, role: role);

Future<void> _pump(WidgetTester tester, DisputeModel dispute) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        disputeDetailProvider(
          dispute.slug,
        ).overrideWith((ref) async => dispute),
        siblingDisputesProvider(
          dispute.slug,
        ).overrideWith((ref) async => const []),
        manualCouriersProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: DisputeDetailPage(disputeSlug: dispute.slug),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the seller gets the action picker on a new complaint', (
    tester,
  ) async {
    await _pump(tester, _dispute(DisputeRole.seller));
    expect(find.text('Detail komplain'), findsOneWidget);
    expect(find.text('Pilih tindakan'), findsOneWidget);
    expect(find.text('Refund penuh ke pembeli'), findsOneWidget);
    expect(find.text('Minta retur barang'), findsOneWidget);
    expect(find.textContaining('Batas respons kamu'), findsOneWidget);

    await tester.tap(find.text('Tawarkan refund sebagian'));
    await tester.pumpAndSettle();
    expect(find.text('Tawarkan'), findsOneWidget);

    // The discussion and history sit below the actions.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Kartu datang dalam keadaan tertekuk'),
      300,
      scrollable: list,
    );
    await tester.scrollUntilVisible(
      find.text('Komplain dibuka pembeli'),
      300,
      scrollable: list,
    );
  });

  testWidgets('the buyer waits on the seller, and can withdraw', (
    tester,
  ) async {
    await _pump(tester, _dispute(DisputeRole.buyer));
    expect(find.text('Pilih tindakan'), findsNothing);
    expect(find.text('Batalkan Komplain'), findsOneWidget);
    // Web's header action, above everything else.
    expect(find.text('Minta bantuan admin'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Minta bantuan admin')).dy,
      lessThan(tester.getTopLeft(find.text('Diskusi & bukti')).dy),
    );
    expect(find.textContaining('Batas respons penjual'), findsOneWidget);
  });

  testWidgets('the buyer answers a partial refund offer', (tester) async {
    await _pump(
      tester,
      _dispute(DisputeRole.buyer, status: 'awaiting_buyer', proposed: 50000),
    );
    expect(find.text('Penjual menawarkan refund Rp50.000'), findsOneWidget);
    expect(find.text('Terima'), findsOneWidget);
    expect(find.text('Tolak'), findsOneWidget);
  });
}
