import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendar/application/week_lane_layout.dart';

WeekLaneItem _item(int startCol, int endCol, {bool isMine = false}) {
  return WeekLaneItem(startCol: startCol, endCol: endCol, isMine: isMine);
}

void main() {
  group('assignWeekLanes', () {
    test('自分の予定は長期予定より上のレーンに置かれる', () {
      // 夏休み（週全体）と自分の予定（火〜水）。開始列は夏休みの方が早い。
      final lanes = assignWeekLanes([_item(0, 6), _item(2, 3, isMine: true)]);

      expect(lanes[1], 0, reason: '自分の予定が最上段');
      expect(lanes[0], 1, reason: '夏休みは 1 段下がる');
    });

    test('自分の予定が複数あっても他の予定より上に詰まる', () {
      final lanes = assignWeekLanes([
        _item(0, 6),
        _item(0, 6),
        _item(1, 2, isMine: true),
        _item(4, 5, isMine: true),
      ]);

      // 重ならない自分の予定 2 件は同じレーン 0 を共有する。
      expect(lanes[2], 0);
      expect(lanes[3], 0);
      expect(lanes[0], 1);
      expect(lanes[1], 2);
    });

    test('重なる自分の予定はレーン 0 から順に積まれる', () {
      final lanes = assignWeekLanes([
        _item(0, 6),
        _item(1, 4, isMine: true),
        _item(2, 5, isMine: true),
      ]);

      expect(lanes[1], 0);
      expect(lanes[2], 1);
      expect(lanes[0], 2);
    });

    test('自分の予定が無ければ開始列順の詰め方（従来の貪欲彩色）と同じ', () {
      final lanes = assignWeekLanes([
        _item(0, 1),
        _item(0, 3),
        _item(2, 4),
        _item(5, 6),
      ]);

      expect(lanes, [0, 1, 0, 0]);
    });

    test('自分の予定が空けた上位レーンの隙間は他の予定が埋める', () {
      // 自分の予定（水〜木）が先にレーン 0 を取るが、月〜火のレーン 0 は空いている。
      final lanes = assignWeekLanes([_item(0, 1), _item(2, 3, isMine: true)]);

      expect(lanes[1], 0);
      expect(lanes[0], 0, reason: '隙間を埋めるのでレーン総数は増えない');
    });

    test('列占有で判定するのでレーン総数が無駄に増えない', () {
      // 終了列だけを覚える貪欲彩色だと、自分の予定を先に置いた時点でレーン 0 の
      // 終了列が木になり、月〜火の予定がレーン 1 へ落ちてレーンが 3 段になる。
      final lanes = assignWeekLanes([
        _item(0, 1),
        _item(5, 6),
        _item(2, 4, isMine: true),
      ]);

      expect(lanes, [0, 0, 0]);
    });

    test('同順位は入力順（呼び出し側の表示優先度順）を保つ', () {
      // 同じ列範囲で重なる 3 件。入力順にレーン 0,1,2 が割り当たる。
      final lanes = assignWeekLanes([_item(1, 2), _item(1, 2), _item(1, 2)]);

      expect(lanes, [0, 1, 2]);
    });

    test('単日どうしが隣り合っても同じレーンを共有する', () {
      final lanes = assignWeekLanes([
        _item(0, 0),
        _item(1, 1),
        _item(2, 2, isMine: true),
      ]);

      expect(lanes, [0, 0, 0]);
    });

    test('空の入力では空を返す', () {
      expect(assignWeekLanes(const []), isEmpty);
    });
  });
}
