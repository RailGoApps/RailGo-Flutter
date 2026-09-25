// 离线库 SQL 构造：LIKE 通配符转义（审计 B-03）
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/storage/offline_db.dart';

void main() {
  group('buildTrainPreselectSql LIKE 转义', () {
    test("非数字开头：\\ % _ 转义 + 单引号双写 + ESCAPE 子句", () {
      final sqls = buildTrainPreselectSql(r"G%'_\D");
      expect(sqls, hasLength(1));
      final sql = sqls.first;
      expect(sql, contains(r"G\%''\_\\D")); // 转义后的关键词（单引号双写）
      expect(sql, contains(r"ESCAPE '\'"));
      expect(sql, isNot(contains(r"%G%")));
    });

    test('数字开头：两条 LIKE 均带 ESCAPE 子句，下划线被转义', () {
      final sqls = buildTrainPreselectSql('12_3');
      expect(sqls, hasLength(1));
      final sql = sqls.first;
      expect(sql, contains(r'12\_3'));
      // 两条 LIKE（复车次下划线变体 + 普通形式）都显式声明转义符
      expect(sql, contains(r"ESCAPE '\'"));
      expect(RegExp(r"ESCAPE '\\'").allMatches(sql).length, 2);
    });

    test('空输入返回空列表', () {
      expect(buildTrainPreselectSql(''), isEmpty);
      expect(buildTrainPreselectSql('   '), isEmpty);
    });
  });
}
