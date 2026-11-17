import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/services/feedback_service.dart';

void main() {
  test('Contact us query types match what the database rules accept', () {
    expect(FeedbackType.values.map((t) => t.name), ['question', 'problem', 'idea', 'account', 'helpers', 'deals', 'praise', 'other']);
    for (final t in FeedbackType.values) {
      expect(t.label, isNotEmpty);
    }
  });
}
