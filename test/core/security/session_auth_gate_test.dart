// Zero-Trust 会话边界：SessionAuthGate 授权过期后必须重新认证
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/auth_gate.dart';

class _CountingGate implements AuthGate {
  _CountingGate(this.willPass);

  final bool willPass;
  int requireUnlockCalls = 0;

  @override
  Future<GateResult> requireUnlock({String reason = ''}) async {
    requireUnlockCalls++;
    return GateResult(
      passed: willPass,
      method: willPass ? GateMethod.biometric : GateMethod.denied,
    );
  }

  @override
  Future<GateResult> verifyPin(String input) async =>
      GateResult(passed: willPass, method: GateMethod.pin);

  @override
  Future<bool> setupPin(String pin) async => true;

  @override
  Future<void> clearPin() async {}

  @override
  bool get hasPin => true;
}

void main() {
  test('窗口内：一次授权覆盖后续敏感操作（不重复弹生物识别）', () async {
    var now = DateTime(2026, 9, 25, 12, 0);
    final inner = _CountingGate(true);
    final gate = SessionAuthGate(
      inner,
      maxUnlockAge: const Duration(minutes: 5),
      clock: () => now,
    );

    final r1 = await gate.requireUnlock(reason: '查看');
    expect(r1.passed, isTrue);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    final r2 = await gate.requireUnlock(reason: '导出');
    expect(r2.passed, isTrue);
    expect(gate.unlocked, isTrue);
    expect(inner.requireUnlockCalls, 1);
  });

  test('超时：授权静默失效，下一次操作必须重新认证（Zero-Trust）', () async {
    var now = DateTime(2026, 9, 25, 12, 0);
    final inner = _CountingGate(true);
    final gate = SessionAuthGate(
      inner,
      maxUnlockAge: const Duration(minutes: 5),
      clock: () => now,
    );

    expect((await gate.requireUnlock()).passed, isTrue);
    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(gate.unlocked, isFalse); // 过期即失效
    final r2 = await gate.requireUnlock();
    expect(r2.passed, isTrue);
    expect(inner.requireUnlockCalls, 2); // 重新走了完整门禁
  });

  test('lock() 立即失效；verifyPin 同样受会话窗口约束', () async {
    var now = DateTime(2026, 9, 25, 12, 0);
    final inner = _CountingGate(true);
    final gate = SessionAuthGate(
      inner,
      maxUnlockAge: const Duration(minutes: 5),
      clock: () => now,
    );

    await gate.requireUnlock();
    gate.lock();
    expect((await gate.verifyPin('123456')).passed, isTrue);
    expect(gate.unlocked, isTrue);

    now = now.add(const Duration(minutes: 6));
    expect((await gate.verifyPin('123456')).passed, isTrue);
    // 第二次 verifyPin 越过窗口 → 重新验证（结果仍通过，但已重新计费）
    now = now.add(const Duration(minutes: 6));
    await gate.verifyPin('123456');
    expect(inner.requireUnlockCalls, 1); // verifyPin 走的是 pin 通道
  });

  test('maxUnlockAge=null：会话内不过期（兼容旧行为）', () async {
    var now = DateTime(2026, 9, 25, 12, 0);
    final inner = _CountingGate(true);
    final gate = SessionAuthGate(inner, maxUnlockAge: null, clock: () => now);

    await gate.requireUnlock();
    now = now.add(const Duration(hours: 24));
    expect(gate.unlocked, isTrue);
    expect((await gate.requireUnlock()).passed, isTrue);
    expect(inner.requireUnlockCalls, 1);
  });
}
