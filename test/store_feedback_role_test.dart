import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/repository/models/store_feedback.dart';

/// `get_feedback_list` rows carry `rated_role` — the side of the order the
/// rated user was on — which the Penilaian tab labels and filters by.
void main() {
  Map<String, dynamic> row(Object? role) => {
    'id': 1,
    'feedback': 'positive',
    'created_at': '2026-10-01T00:00:00Z',
    'rated_role': role,
  };

  test('reads the rated side of the order', () {
    expect(StoreFeedback.fromRow(row('seller')).ratedRole, FeedbackRole.seller);
    expect(StoreFeedback.fromRow(row('buyer')).ratedRole, FeedbackRole.buyer);
  });

  test('a row without the column has no role rather than a guess', () {
    expect(StoreFeedback.fromRow(row(null)).ratedRole, isNull);
    expect(StoreFeedback.fromRow(row('admin')).ratedRole, isNull);
  });

  test('sends the raw value p_role expects', () {
    expect(FeedbackRole.seller.raw, 'seller');
    expect(FeedbackRole.buyer.raw, 'buyer');
    expect(FeedbackRole.buyer.noun, 'pembeli');
  });
}
