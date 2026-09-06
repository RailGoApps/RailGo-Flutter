// test/features/certificate/certificate_repository_test.dart
//
// 证件库：SM4 往返 + 门禁强制（红队：绕过门禁必须被拒绝）
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/auth_gate.dart';
import 'package:railgo/core/security/key_service.dart';
import 'package:railgo/features/certificate/certificate_repository.dart';

class _FixedKey implements Sm4KeySource {
  const _FixedKey(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List> obtain() async => bytes;
}

class _FakeGate implements AuthGate {
  const _FakeGate(this.willPass);
  final bool willPass;
  @override
  Future<GateResult> requireUnlock({String reason = ''}) async {
    return GateResult(passed: willPass, method: willPass ? GateMethod.biometric : GateMethod.denied);
  }

  @override
  Future<GateResult> verifyPin(String input) async =>
      GateResult(passed: false, method: GateMethod.denied);
  @override
  Future<bool> setupPin(String pin) async => false;
  @override
  Future<void> clearPin() async {}
  @override
  bool get hasPin => false;
}

class _MemStorage implements CertificateStorage {
  _MemStorage();
  final Map<String, String> db = {};
  @override
  Future<List<String>> loadAll() async => db.values.toList();
  @override
  Future<void> store(String id, String payload) async => db[id] = payload;
  @override
  Future<void> remove(String id) async => db.remove(id);
}

void main() {
  const cert = Certificate(
    id: 'c1',
    type: CertType.residentId,
    number: '110101199003077758',
    name: '张三',
    phone: '13800000000',
    birthDate: '19900307',
  );

  test('SM4 加密落库 → 解密还原全部字段（含中文）', () async {
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(Uint8List.fromList(List<int>.generate(16, (i) => i))),
      storage: _MemStorage(),
    );
    await repo.save(cert);
    final all = await repo.unlockAll();
    expect(all.length, 1);
    expect(all.first.name, '张三');
    expect(all.first.number, '110101199003077758');
    expect(all.first.type, CertType.residentId);
    expect(all.first.phone, '13800000000');
    expect(all.first.birthDate, '19900307');
  });

  test('存储中绝无明文（号码/姓名不可被直接 grep）', () async {
    final storage = _MemStorage();
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(Uint8List.fromList(List<int>.generate(16, (i) => i + 1))),
      storage: storage,
    );
    await repo.save(cert);
    final raw = storage.db.values.join();
    expect(raw.contains('张三'), isFalse);
    expect(raw.contains('110101199003077758'), isFalse);
  });

  test('门禁拒绝 → 读写均抛 GateDeniedException（红队：无绕过路径）', () async {
    final repo = CertificateRepository(
      gate: const _FakeGate(false),
      keySource: _FixedKey(Uint8List.fromList(List<int>.generate(16, (i) => i))),
      storage: _MemStorage(),
    );
    await expectLater(repo.save(cert), throwsA(isA<GateDeniedException>()));
    await expectLater(repo.unlockAll(), throwsA(isA<GateDeniedException>()));
  });

  test('密钥错误 → 解密抛 FormatException 而非泄漏乱码', () {
    final k1 = CertificateCrypto(Uint8List.fromList(List<int>.generate(16, (i) => i)));
    final k2 = CertificateCrypto(Uint8List.fromList(List<int>.generate(16, (i) => 255 - i)));
    final payload = k1.encrypt(cert);
    expect(() => k2.decrypt(payload), throwsFormatException);
  });
}
