import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/supabase/business_conflict.dart';

void main() {
  test('new conflicts and exact legacy business errors are recoverable', () {
    expect(isBusinessConflict('PT409', 'private details'), isTrue);
    for (final message in [
      'expense changed',
      'list access changed',
      'list changed',
      'list item changed',
      'moderation case changed',
      'moderation restriction changed',
      'relationship changed',
      'settlement changed',
      'split changed',
      'template category changed',
      'template changed',
      'template send changed'
    ]) {
      expect(isBusinessConflict('40001', message), isTrue);
    }
  });
  test('engine serialization and unrelated errors are never business conflicts',
      () {
    expect(
        isBusinessConflict(
            '40001', 'could not serialize access due to concurrent update'),
        isFalse);
    expect(isBusinessConflict('40001', 'unknown state'), isFalse);
    expect(isBusinessConflict('XX000', 'list changed'), isFalse);
    expect(isBusinessConflict(null, 'list changed'), isFalse);
  });
}
