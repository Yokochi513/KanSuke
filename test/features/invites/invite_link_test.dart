import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/invites/application/invite_link.dart';

void main() {
  group('招待リンクの URL 規約（FR-9 / Issue #90）', () {
    test('発行したリンクは kansuke://invite?token=... になる', () {
      final link = buildInviteLink('abc123');

      expect(link.toString(), 'kansuke://invite?token=abc123');
      expect(parseInviteToken(link), 'abc123');
    });

    test('トークンに URL 予約文字が含まれてもエスケープして往復できる', () {
      final link = buildInviteLink('a+b/c=d&e');

      expect(parseInviteToken(link), 'a+b/c=d&e');
    });

    test('Web は任意パスの ?token= を受け付ける', () {
      expect(
        parseInviteToken(Uri.parse('https://example.com/?token=abc123')),
        'abc123',
      );
      expect(
        parseInviteToken(Uri.parse('http://localhost:8080/invite?token=abc')),
        'abc',
      );
    });

    test('貼り付けはリンクでもトークン単体でも受け付ける（Web の受け口）', () {
      expect(parseInvitePaste(' kansuke://invite?token=abc123 '), 'abc123');
      expect(parseInvitePaste('https://example.com/?token=abc123'), 'abc123');
      // リンクの一部だけを渡された場合（トークンだけコピーした等）。
      expect(parseInvitePaste('abc123'), 'abc123');
    });

    test('貼り付けが空・別スキームのリンクなら受け付けない', () {
      expect(parseInvitePaste('  '), isNull);
      expect(parseInvitePaste('kansuke://other?token=abc'), isNull);
      expect(parseInvitePaste('https://example.com/'), isNull);
    });

    test('招待リンクでない URI からはトークンを取り出さない', () {
      expect(parseInviteToken(Uri.parse('kansuke://invite')), isNull);
      expect(parseInviteToken(Uri.parse('kansuke://invite?token=')), isNull);
      // 別スキーム・別ホストのリンクは無視する。
      expect(parseInviteToken(Uri.parse('kansuke://other?token=abc')), isNull);
      expect(parseInviteToken(Uri.parse('myapp://invite?token=abc')), isNull);
    });
  });
}
