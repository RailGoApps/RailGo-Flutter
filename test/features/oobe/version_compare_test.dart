// 网关版本串比较（"2.0.6 Build 20006" 型）
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/oobe/version_compare.dart';

void main() {
  test('提取首个 x.y.z 三元组', () {
    expect(versionTuple('2.0.6 Build 20006'), [2, 0, 6]);
    expect(versionTuple('v3.1.0-beta.2'), [3, 1, 0]);
    expect(versionTuple('无版本'), isNull);
    expect(versionTuple('61'), isNull);
  });

  test('严格新于才提示更新；相等/更旧/不可解析均不提示', () {
    expect(isNewerVersion('3.1.0 Build 30001', '3.0.0 Build 30000'), isTrue);
    expect(isNewerVersion('2.0.6 Build 20006', '3.0.0 Build 30000'), isFalse);
    expect(isNewerVersion('3.0.0 Build 30000', '3.0.0 Build 30000'), isFalse);
    expect(isNewerVersion('2.0.6 Build 20006', '未下载'), isFalse);
    expect(isNewerVersion('61', '3.0.0 Build 30000'), isFalse);
  });
}
