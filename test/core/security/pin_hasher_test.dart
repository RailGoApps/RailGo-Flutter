// PIN 哈希：v2 100k 轮写入 + 旧 5000 轮透明升级 + 恒时比较
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/auth_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('迭代次数影响结果；恒时比较基本性质', () {
    const h = PinHasher();
    final a = h.hash('123456', 'salt', iterations: 2);
    final b = h.hash('123456', 'salt', iterations: 3);
    expect(a == b, isFalse);
    expect(h.fixedTimeEquals(a, a), isTrue);
    expect(h.fixedTimeEquals(a, b), isFalse);
    expect(h.fixedTimeEquals('abc', 'ab'), isFalse);
  });

  test('setupPin 写入 v2（100k 轮）；verifyPin 正确接受/拒绝', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(prefs: prefs);

    expect(await gate.setupPin('123456'), isTrue);
    expect(prefs.getString('railgo.pin.hash')!.startsWith('v2:'), isTrue);
    expect(gate.hasPin, isTrue);

    final ok = await gate.verifyPin('123456');
    expect(ok.passed, isTrue);
    expect(ok.method, GateMethod.pin);

    final bad = await gate.verifyPin('000000');
    expect(bad.passed, isFalse);

    expect(await gate.setupPin('12'), isFalse); // 非 6 位拒绝
  });

  test('旧 5000 轮哈希：验证通过后透明升级为 v2（用户无感）', () async {
    const hasher = PinHasher();
    const salt = 'aabbccddeeff00112233445566778899';
    SharedPreferences.setMockInitialValues({
      'railgo.pin.salt': salt,
      'railgo.pin.hash': hasher.hash('654321', salt), // 旧格式（无前缀）
    });
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(prefs: prefs);

    final ok = await gate.verifyPin('654321');
    expect(ok.passed, isTrue);

    // 存储已升级为 v2，且校验值仍匹配
    final stored = prefs.getString('railgo.pin.hash')!;
    expect(stored.startsWith('v2:'), isTrue);
    expect(
      hasher.fixedTimeEquals(
        hasher.hash('654321', salt, iterations: PinHasher.kCurrentIterations),
        stored.substring(3),
      ),
      isTrue,
    );

    // 错误 PIN 在旧格式上依旧拒绝
    final bad = await gate.verifyPin('123456');
    expect(bad.passed, isFalse);
  });
}
