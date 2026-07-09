import '../../../models/models.dart';

/// カレンダー編集画面への遷移引数。
///
/// - [CalendarEditArgs.create]: 新規カレンダーを作成する。
/// - [CalendarEditArgs.edit]: 既存カレンダーの名前・参加者を編集する。
class CalendarEditArgs {
  const CalendarEditArgs.create() : calendar = null;

  const CalendarEditArgs.edit(Calendar this.calendar);

  /// 編集対象の既存カレンダー。新規作成時は null。
  final Calendar? calendar;

  bool get isCreate => calendar == null;
}
