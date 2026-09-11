import 'package:anx_reader/service/convert_to_epub/txt/txt_title_helper.dart';
import 'package:test/test.dart';

void main() {
  group('extractDisplayTitle', () {
    test('extracts title from 《书名》', () {
      expect(extractDisplayTitle('《诛仙》'), equals('诛仙'));
      expect(extractDisplayTitle('【精校】《大奉打更人》【完本】'), equals('大奉打更人'));
      expect(extractDisplayTitle('[校对版]《诡秘之主》'), equals('诡秘之主'));
    });

    test('retains authentic title semantics like Chinese colons and subtitles', () {
      expect(extractDisplayTitle('《三体：黑暗森林》'), equals('三体：黑暗森林'));
      expect(extractDisplayTitle('《哈利·波特与魔法石》'), equals('哈利·波特与魔法石'));
    });

    test('extracts title from 【书名】', () {
      expect(extractDisplayTitle('【大奉打更人】'), equals('大奉打更人'));
      expect(extractDisplayTitle('【精校】【大奉打更人】'), equals('大奉打更人'));
      expect(extractDisplayTitle('【大奉打更人】【完本】'), equals('大奉打更人'));
    });

    test('extracts title from [书名]', () {
      expect(extractDisplayTitle('[诡秘之主]'), equals('诡秘之主'));
      expect(extractDisplayTitle('[精校][诡秘之主][全本]'), equals('诡秘之主'));
    });

    test('strips clear leading "书名：" and "书名:" prefix', () {
      expect(extractDisplayTitle('书名：雪中悍刀行'), equals('雪中悍刀行'));
      expect(extractDisplayTitle('书名:雪中悍刀行'), equals('雪中悍刀行'));
      expect(extractDisplayTitle('【精校】书名：雪中悍刀行'), equals('雪中悍刀行'));
      expect(extractDisplayTitle('书名：《哈利·波特》'), equals('哈利·波特'));
    });

    test('strips trailing author marker when no brackets are present', () {
      expect(
        extractDisplayTitle('书名：雪中悍刀行 作者：烽火戏诸侯'),
        equals('雪中悍刀行'),
      );
      expect(
        extractDisplayTitle('雪中悍刀行 作者：烽火戏诸侯'),
        equals('雪中悍刀行'),
      );
    });

    test('strips tightly attached trailing author marker (作者/著) without deleting book title', () {
      expect(extractDisplayTitle('凡人修仙传作者：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传作者:忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传著:忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传原著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传原著:忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传 作者：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传 著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传 原著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传 原著:忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传_作者：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传_著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传_原著：忘语'), equals('凡人修仙传'));
      expect(extractDisplayTitle('凡人修仙传_原著:忘语'), equals('凡人修仙传'));
    });

    test('preserves authentic title semantics and does not mistakenly strip regular title words containing 著', () {
      expect(extractDisplayTitle('世界名著：哈姆雷特'), equals('世界名著：哈姆雷特'));
      expect(extractDisplayTitle('中国古典名著：红楼梦'), equals('中国古典名著：红楼梦'));
      expect(extractDisplayTitle('名著：三国演义'), equals('名著：三国演义'));
      expect(extractDisplayTitle('现代学术专著：相对论导引'), equals('现代学术专著：相对论导引'));
      expect(extractDisplayTitle('历史巨著：史记全本'), equals('历史巨著：史记全本'));
      expect(extractDisplayTitle('哲学经典论著：资本论'), equals('哲学经典论著：资本论'));
      expect(extractDisplayTitle('世界名著 著：莎士比亚'), equals('世界名著'));
      expect(extractDisplayTitle('世界名著 原著：莎士比亚'), equals('世界名著'));
      expect(extractDisplayTitle('世界名著原著：莎士比亚'), equals('世界名著'));
    });

    test('strips known packaging modifier tags without deleting book title', () {
      expect(extractDisplayTitle('[精校] 斗破苍穹'), equals('斗破苍穹'));
      expect(extractDisplayTitle('【完本】剑来 (精校)'), equals('剑来'));
    });

    test('falls back to Unknown when input consists purely of modifier tags or empty brackets', () {
      expect(extractDisplayTitle('【精校】'), equals('Unknown'));
      expect(extractDisplayTitle('[完本]'), equals('Unknown'));
      expect(extractDisplayTitle('【精校】【完结版】'), equals('Unknown'));
      expect(extractDisplayTitle('[精校][全本]'), equals('Unknown'));
      expect(extractDisplayTitle('(精校版)'), equals('Unknown'));
      expect(extractDisplayTitle('【精校】[]'), equals('Unknown'));
    });

    test('preserves plain filename when no brackets or prefixes match', () {
      expect(extractDisplayTitle('凡人修仙传'), equals('凡人修仙传'));
    });

    test('handles empty or whitespace-only inputs gracefully', () {
      expect(extractDisplayTitle(''), equals('Unknown'));
      expect(extractDisplayTitle('   '), equals('Unknown'));
      expect(extractDisplayTitle('《》'), equals('Unknown'));
      expect(extractDisplayTitle('【】'), equals('Unknown'));
      expect(extractDisplayTitle('[]'), equals('Unknown'));
      expect(extractDisplayTitle('《  》'), equals('Unknown'));
      expect(extractDisplayTitle('【  】'), equals('Unknown'));
      expect(extractDisplayTitle('[  ]'), equals('Unknown'));
      expect(extractDisplayTitle('()'), equals('Unknown'));
      expect(extractDisplayTitle('（）'), equals('Unknown'));
      expect(extractDisplayTitle('(   )'), equals('Unknown'));
      expect(extractDisplayTitle('（   ）'), equals('Unknown'));
      expect(extractDisplayTitle('《　》'), equals('Unknown'));
      expect(extractDisplayTitle('【　】'), equals('Unknown'));
      expect(extractDisplayTitle('[　]'), equals('Unknown'));
      expect(extractDisplayTitle('《》【】[]'), equals('Unknown'));
      expect(extractDisplayTitle('作者：忘语'), equals('Unknown'));
      expect(extractDisplayTitle('著：忘语'), equals('Unknown'));
      expect(extractDisplayTitle('原著：忘语'), equals('Unknown'));
      expect(extractDisplayTitle('原著:忘语'), equals('Unknown'));
    });
  });

  group('extractAuthor', () {
    test('extracts author from common author patterns', () {
      expect(extractAuthor('《诛仙》作者：萧鼎'), equals('萧鼎'));
      expect(extractAuthor('《诛仙》作者:萧鼎'), equals('萧鼎'));
      expect(extractAuthor('《三体》著：刘慈欣'), equals('刘慈欣'));
      expect(extractAuthor('《三体》著: 刘慈欣 [精校]'), equals('刘慈欣'));
      expect(extractAuthor('凡人修仙传作者：忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传著：忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传原著：忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传原著:忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传 原著：忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传 原著:忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传_原著：忘语'), equals('忘语'));
      expect(extractAuthor('凡人修仙传_原著:忘语'), equals('忘语'));
      expect(extractAuthor('《诛仙》原著：萧鼎'), equals('萧鼎'));
      expect(extractAuthor('原著：忘语'), equals('忘语'));
      expect(extractAuthor('原著:忘语'), equals('忘语'));
      expect(extractAuthor('世界名著 原著：莎士比亚'), equals('莎士比亚'));
      expect(extractAuthor('世界名著原著：莎士比亚'), equals('莎士比亚'));
      expect(extractAuthor('世界名著 著：莎士比亚'), equals('莎士比亚'));
    });

    test('returns Unknown when author is absent', () {
      expect(extractAuthor('雪中悍刀行'), equals('Unknown'));
      expect(extractAuthor(''), equals('Unknown'));
      expect(extractAuthor('世界名著：哈姆雷特'), equals('Unknown'));
    });
  });

  group('toSafePathComponent', () {
    test('replaces illegal filesystem characters and control codes', () {
      expect(
        toSafePathComponent('book/name\\with:illegal*chars?"<>|'),
        equals('book_name_with_illegal_chars'),
      );
      expect(
        toSafePathComponent('hello\x00world\x1f'),
        equals('hello_world'),
      );
    });

    test('replaces Chinese fullwidth equivalent characters', () {
      expect(
        toSafePathComponent('三体：黑暗森林'),
        equals('三体_黑暗森林'),
      );
      expect(
        toSafePathComponent('哈利·波特？＜全集＞“珍藏”／＼｜＊'),
        equals('哈利·波特_全集_珍藏'),
      );
    });

    test('collapses consecutive whitespace and underscores, and trims edges', () {
      expect(
        toSafePathComponent('   ___my___book___name___   '),
        equals('my_book_name'),
      );
      expect(
        toSafePathComponent('...my.book.name...'),
        equals('my.book.name'),
      );
    });

    test('falls back to default for empty or invalid inputs', () {
      expect(toSafePathComponent(''), equals('book'));
      expect(toSafePathComponent('   '), equals('book'));
      expect(toSafePathComponent(':::???///'), equals('book'));
      expect(
        toSafePathComponent(':::???///', fallback: 'untitled'),
        equals('untitled'),
      );
    });

    test('enforces reasonable max length without cutting surrogate code points', () {
      final longName = '书' * 100;
      final safe = toSafePathComponent(longName, maxLength: 30);
      expect(safe.runes.length, equals(30));
      expect(safe, equals('书' * 30));
    });

    test('trims trailing dots and underscores created by length truncation', () {
      final input = 'abc_' * 20;
      final safe = toSafePathComponent(input, maxLength: 7);
      expect(safe.endsWith('_'), isFalse);
      expect(safe.endsWith('.'), isFalse);
    });
  });
}
