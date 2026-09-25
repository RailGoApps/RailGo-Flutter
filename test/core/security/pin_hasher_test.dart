// PIN 哈希：v3 PBKDF2 写入 + v2/旧 5000 轮透明升级 + 恒时比较 + 锁定退避
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

  test('setupPin 写入 v3（PBKDF2）；verifyPin 正确接受/拒绝', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(
        prefs: prefs, hasher: const PinHasher(pbkdf2Iterations: 200));

    expect(await gate.setupPin('123456'), isTrue);
    expect(prefs.getString('railgo.pin.hash')!.startsWith('v3:'), isTrue);
    expect(gate.hasPin, isTrue);

    final ok = await gate.verifyPin('123456');
    expect(ok.passed, isTrue);
    expect(ok.method, GateMethod.pin);

    final bad = await gate.verifyPin('000000');
    expect(bad.passed, isFalse);

    expect(await gate.setupPin('12'), isFalse); // 非 6 位拒绝
  });

  test('旧 5000 轮哈希：验证通过后透明升级为 v3（用户无感）', () async {
    // SHA 迭代次数与 PBKDF2 轮数解耦：用低轮 PBKDF2 加速测试
    const hasher = PinHasher(pbkdf2Iterations: 200);
    const salt = 'aabbccddeeff00112233445566778899';
    SharedPreferences.setMockInitialValues({
      'railgo.pin.salt': salt,
      'railgo.pin.hash': hasher.hash('654321', salt), // 旧格式（无前缀）
    });
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(prefs: prefs, hasher: hasher);

    final ok = await gate.verifyPin('654321');
    expect(ok.passed, isTrue);

    // 存储已升级为 v3，且校验值仍匹配
    final stored = prefs.getString('railgo.pin.hash')!;
    expect(stored.startsWith('v3:'), isTrue);
    expect(
      hasher.fixedTimeEquals(
        hasher.pbkdf2Hash('654321', salt),
        stored.substring(3),
      ),
      isTrue,
    );

    // 错误 PIN 在旧格式上依旧拒绝
    final bad = await gate.verifyPin('123456');
    expect(bad.passed, isFalse);
  });

  test('v2 迭代 SHA-256 哈希：验证通过后透明升级为 v3', () async {
    const salt = '11223344556677889900aabbccddeeff';
    SharedPreferences.setMockInitialValues({
      'railgo.pin.salt': salt,
      'railgo.pin.hash':
          'v2:${const PinHasher().hash('246802', salt, iterations: PinHasher.kCurrentIterations)}',
    });
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(
        prefs: prefs, hasher: const PinHasher(pbkdf2Iterations: 200));

    final ok = await gate.verifyPin('246802');
    expect(ok.passed, isTrue);
    final stored = prefs.getString('railgo.pin.hash')!;
    expect(stored.startsWith('v3:'), isTrue);
  });

  test('PBKDF2：同盐同 PIN 一致；不同盐/不同轮数不同', () {
    const h = PinHasher(pbkdf2Iterations: 200);
    final a = h.pbkdf2Hash('123456', 'saltA');
    final b = h.pbkdf2Hash('123456', 'saltA');
    final c = h.pbkdf2Hash('123456', 'saltB');
    final d =
        const PinHasher(pbkdf2Iterations: 201).pbkdf2Hash('123456', 'saltA');
    expect(a, b);
    expect(a, isNot(c));
    expect(a, isNot(d));
    expect(a.length, 64); // 32 字节 hex
  });

  test('PIN 连续错误 5 次锁定；锁定期正确 PIN 也拒绝；到期自动恢复', () async {
    var now = DateTime(2026, 1, 1, 12);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(
      prefs: prefs,
      hasher: const PinHasher(pbkdf2Iterations: 100),
      clock: () => now,
    );
    await gate.setupPin('123456');

    for (var i = 0; i < LocalAuthGate.kMaxPinAttempts; i++) {
      final r = await gate.verifyPin('000000');
      expect(r.passed, isFalse);
    }
    expect(gate.pinLockedUntil, isNotNull);
    expect(gate.remainingPinAttempts, 0);

    // 锁定期内：正确 PIN 也被拒绝（防穷举关键语义）
    final lockedOk = await gate.verifyPin('123456');
    expect(lockedOk.passed, isFalse);

    // 首次锁定 30s：时间到后恢复
    now = now.add(const Duration(seconds: 31));
    expect(gate.pinLockedUntil, isNull);
    final ok = await gate.verifyPin('123456');
    expect(ok.passed, isTrue);
    expect(gate.remainingPinAttempts, LocalAuthGate.kMaxPinAttempts);
  });

  test('锁定时长指数退避且 15 分钟封顶', () async {
    var now = DateTime(2026, 1, 1, 12);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gate = LocalAuthGate(
      prefs: prefs,
      hasher: const PinHasher(pbkdf2Iterations: 50),
      clock: () => now,
    );
    await gate.setupPin('123456');

    // 连续触发 6 轮锁定：30s → 60s → 120s → 240s → 480s → 960s→封顶 900s
    final expected = <int>[30, 60, 120, 240, 480, 900];
    for (final secs in expected) {
      for (var i = 0; i < LocalAuthGate.kMaxPinAttempts; i++) {
        await gate.verifyPin('000000');
      }
      final lock = gate.pinLockedUntil;
      expect(lock, isNotNull);
      expect(lock!.difference(now).inSeconds, secs);
      now = now.add(Duration(seconds: secs + 1)); // 越过锁定期
    }
  });
}
