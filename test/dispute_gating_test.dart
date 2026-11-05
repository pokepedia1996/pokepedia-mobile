import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/dispute_model.dart';
import 'package:pokepedia_mobile/features/orders/utils/dispute_gating.dart';

/// The dispute page's action rules, ported from web's
/// `dispute-detail-gating.ts`, `dispute-resolution-paths.ts` and `sla.ts`.
DisputeModel _dispute({
  String status = 'awaiting_seller',
  String reason = 'damaged',
  DisputeRole role = DisputeRole.buyer,
  int? proposed,
  String? returnRequestedAt,
  String? returnDeadline,
  String? returnTracking,
  String? responseDeadline,
  String? evidenceFrom,
  int? shortQuantity,
  List<String> events = const [],
}) => DisputeModel.fromRow({
  'id': 7,
  'slug': 'dsp-261028-abcde',
  'current_status': status,
  'reason_category': reason,
  'proposed_refund_amount': proposed,
  'return_requested_at': returnRequestedAt,
  'return_deadline_at': returnDeadline,
  'return_tracking': returnTracking,
  'response_deadline_at': responseDeadline,
  'evidence_requested_from': evidenceFrom,
  'short_quantity': shortQuantity,
  'opened_at': '2026-10-20T10:00:00Z',
  'settlements': {
    'slug': 'b1c2d3e4-0000-4000-8000-000000000000',
    'escrow_amount': 300000,
    'shipping_cost': 15000,
    'condition': 'NM',
    'order_items': {
      'slug': 'item-1',
      'order_id': 42,
      'order_number': 'pk-1-a',
      'matched_quantity': 3,
      'cards': {'name_id': 'Pikachu ex'},
    },
  },
  'dispute_events': [
    for (final type in events)
      {'event_type': type, 'created_at': '2026-10-21T10:00:00Z'},
  ],
}, role: role);

void main() {
  group('parsing', () {
    test('reads the settlement, item and package off the embed', () {
      final d = _dispute();
      expect(d.id, 7);
      expect(d.settlementSlug, startsWith('b1c2'));
      expect(d.escrowAmount, 300000);
      expect(d.shippingCost, 15000);
      expect(d.item?.slug, 'item-1');
      expect(d.item?.orderId, 42);
      expect(d.item?.cardName, 'Pikachu ex');
    });

    test('events keep types the app has no label for', () {
      final e = DisputeEvent.fromRow({
        'event_type': 'something_new',
        'payload': {'amount': 5000},
      });
      expect(e.label, 'something_new');
      expect(
        DisputeEvent.fromRow({
          'event_type': 'partial_refund_proposed',
          'payload': {'amount': 50000},
        }).detail,
        'Tawaran Rp50.000',
      );
    });

    test('evidence sent together reads as one message', () {
      final messages = groupDisputeMessages(const [
        DisputeEvidence(
          id: 2,
          role: 'seller',
          type: 'photo',
          url: 'https://x/p.jpg',
          submittedAt: '2026-10-21T10:00:00Z',
        ),
        DisputeEvidence(
          id: 1,
          role: 'seller',
          type: 'statement',
          body: 'Sudah dikirim',
          submittedAt: '2026-10-21T10:00:00Z',
        ),
        DisputeEvidence(
          id: 3,
          role: 'buyer',
          type: 'statement',
          body: 'Belum sampai',
          submittedAt: '2026-10-20T10:00:00Z',
        ),
      ]);
      expect(messages.map((m) => m.role), ['buyer', 'seller']);
      expect(messages.last.statement, 'Sudah dikirim');
      expect(messages.last.photoUrls, ['https://x/p.jpg']);
    });
  });

  group('buyer', () {
    test('a partial offer asks for a decision, nothing else', () {
      final s = BuyerDisputeActions.of(
        _dispute(status: 'awaiting_buyer', proposed: 100000),
      );
      expect(s.hasPartialOffer, isTrue);
      expect(s.canRespond, isFalse);
      expect(s.canWithdraw, isTrue);
    });

    test('a return request waits for approval until approved', () {
      final asked = _dispute(
        status: 'awaiting_buyer',
        returnRequestedAt: '2026-10-21T10:00:00Z',
      );
      expect(BuyerDisputeActions.of(asked).awaitingReturnWindow, isTrue);

      final approved = _dispute(
        status: 'awaiting_buyer',
        returnRequestedAt: '2026-10-21T10:00:00Z',
        events: ['return_approved'],
      );
      final s = BuyerDisputeActions.of(approved);
      expect(s.awaitingReturnWindow, isFalse);
      expect(s.returnApproved, isTrue);
    });

    test('an open return window wants the resi', () {
      final s = BuyerDisputeActions.of(
        _dispute(
          status: 'awaiting_buyer',
          returnRequestedAt: '2026-10-21T10:00:00Z',
          returnDeadline: '2026-10-24T10:00:00Z',
        ),
      );
      expect(s.needsReturnTracking, isTrue);
      expect(s.canRespond, isFalse);
    });

    test('a sent resi can no longer be withdrawn from', () {
      final s = BuyerDisputeActions.of(
        _dispute(status: 'awaiting_buyer', returnTracking: 'JNE123'),
      );
      expect(s.canWithdraw, isFalse);
    });

    test('admin review locks withdraw and answers only what admin asked', () {
      final s = BuyerDisputeActions.of(
        _dispute(status: 'admin_review', evidenceFrom: 'both'),
      );
      expect(s.inAdminReview, isTrue);
      expect(s.answersAdminRequest, isTrue);
      expect(s.canWithdraw, isFalse);
    });

    test('a resolved dispute offers nothing', () {
      final s = BuyerDisputeActions.of(_dispute(status: 'resolved'));
      expect(s.isActive, isFalse);
    });
  });

  group('seller', () {
    test('a new complaint is the seller\'s turn', () {
      final s = SellerDisputeActions.of(
        _dispute(status: 'opened', role: DisputeRole.seller),
      );
      expect(s.awaitingSellerResponse, isTrue);
      expect(s.returnInTransit, isFalse);
    });

    test('a resi on the way asks the seller to confirm receipt', () {
      final s = SellerDisputeActions.of(
        _dispute(
          status: 'awaiting_seller',
          role: DisputeRole.seller,
          returnTracking: 'JNE123',
        ),
      );
      expect(s.returnInTransit, isTrue);
    });

    test('options follow the reason, and narrow after a partial offer', () {
      expect(
        sellerDisputeOptions(DisputeReasonCategory.short_, partialUsed: false),
        [
          SellerDisputeAction.message,
          SellerDisputeAction.refundShortfall,
          SellerDisputeAction.escalate,
        ],
      );
      expect(
        sellerDisputeOptions(
          DisputeReasonCategory.notReceived,
          partialUsed: false,
        ),
        isNot(contains(SellerDisputeAction.requestReturn)),
      );
      expect(
        sellerDisputeOptions(DisputeReasonCategory.damaged, partialUsed: true),
        [SellerDisputeAction.fullRefund, SellerDisputeAction.requestReturn],
      );
    });

    test('the shortfall refund is the escrow share of the missing units', () {
      expect(
        shortfallRefundAmount(_dispute(reason: 'short', shortQuantity: 1)),
        100000,
      );
    });
  });

  group('header escalate', () {
    test('the buyer can escalate any active dispute outside admin review', () {
      expect(showsHeaderEscalate(_dispute(status: 'opened')), isTrue);
      expect(showsHeaderEscalate(_dispute(status: 'awaiting_buyer')), isTrue);
      expect(showsHeaderEscalate(_dispute(status: 'admin_review')), isFalse);
      expect(showsHeaderEscalate(_dispute(status: 'resolved')), isFalse);
    });

    test('the seller gets it in the header only when the picker is closed', () {
      expect(
        showsHeaderEscalate(
          _dispute(status: 'opened', role: DisputeRole.seller),
        ),
        isFalse,
      );
      expect(
        showsHeaderEscalate(
          _dispute(status: 'awaiting_buyer', role: DisputeRole.seller),
        ),
        isTrue,
      );
      expect(
        showsHeaderEscalate(
          _dispute(
            status: 'awaiting_seller',
            role: DisputeRole.seller,
            returnTracking: 'JNE123',
          ),
        ),
        isTrue,
      );
    });
  });

  group('deadline', () {
    test('names whose turn it is', () {
      final buyerView = disputeDeadline(
        _dispute(responseDeadline: '2026-10-23T10:00:00Z'),
      );
      expect(buyerView?.label, 'Batas respons penjual');

      final sellerView = disputeDeadline(
        _dispute(
          role: DisputeRole.seller,
          responseDeadline: '2026-10-23T10:00:00Z',
        ),
      );
      expect(sellerView?.label, 'Batas respons kamu');
    });

    test('a partial offer counts down the buyer\'s decision', () {
      final d = disputeDeadline(
        _dispute(
          status: 'awaiting_buyer',
          proposed: 100000,
          responseDeadline: '2026-10-23T10:00:00Z',
        ),
      );
      expect(d?.label, 'Batas keputusan pembeli');
    });

    test('the return window counts down until a resi arrives', () {
      expect(
        disputeDeadline(
          _dispute(
            status: 'awaiting_buyer',
            returnDeadline: '2026-10-24T10:00:00Z',
          ),
        )?.label,
        'Batas kirim resi retur',
      );
      expect(
        disputeDeadline(
          _dispute(
            status: 'awaiting_buyer',
            returnDeadline: '2026-10-24T10:00:00Z',
            returnTracking: 'JNE123',
          ),
        ),
        isNull,
      );
    });

    test('none under admin review', () {
      expect(
        disputeDeadline(
          _dispute(
            status: 'escalated',
            responseDeadline: '2026-10-23T10:00:00Z',
          ),
        ),
        isNull,
      );
    });
  });
}
