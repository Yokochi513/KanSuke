import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/japanese_holidays.dart';

void main() {
  test('内閣府が公開済みの祝日名を返す', () {
    expect(japaneseHolidayName(DateTime(2026, 7, 20)), '海の日');
    expect(japaneseHolidayName(DateTime(2026, 9, 22)), '休日');
  });

  test('祝日ではない日は null を返す', () {
    expect(japaneseHolidayName(DateTime(2026, 7, 7)), isNull);
    expect(isJapaneseHoliday(DateTime(2026, 7, 7)), isFalse);
  });
}
