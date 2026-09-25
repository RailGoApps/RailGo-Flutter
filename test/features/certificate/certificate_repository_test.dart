// 证件库 v2：SM4 往返 + 门禁强制（红队：绕过门禁必须被拒绝）
// + 一人多证分组 + 同号告警 + 旧数据兼容 + 口令信封导出导入。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/crypto/sm4.dart';
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
    return GateResult(
      passed: willPass,
      method: willPass ? GateMethod.biometric : GateMethod.denied,
    );
  }

  @override
  Future<GateResult> verifyPin(String input) async =>
      const GateResult(passed: false, method: GateMethod.denied);

  @override
  Future<bool> setupPin(String pin) async => false;

  @override
  Future<void> clearPin() async {}

  @override
  bool get hasPin => false;
}

class _MemStorage implements CertificateStorage {
  final Map<String, String> db = {};

  @override
  Future<List<String>> loadAll() async => db.values.toList();

  @override
  Future<void> store(String id, String payload) async => db[id] = payload;

  @override
  Future<void> remove(String id) async => db.remove(id);
}

Uint8List _k(int offset) => Uint8List.fromList(
      List<int>.generate(16, (i) => (i + offset) % 256),
    );

void main() {
  const cert = Certificate(
    id: 'c1',
    typeCode: 'ED',
    number: '110101199003077758',
    name: '张三',
    phone: '13800000000',
    birthDate: '19900307',
  );

  test('SM4 加密落库 → 解密还原全部字段（含中文/识读字段）', () async {
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(0)),
      storage: _MemStorage(),
    );
    await repo.save(const Certificate(
      id: 'c2',
      typeCode: 'HZ',
      number: 'E12345678',
      name: 'ZHANG SAN',
      birthDate: '19900307',
      sex: '男',
      nationalityCode: 'CHN',
      nationality: '中国/China',
      expiryDate: '20300307',
      source: CertSource.mrz,
    ));
    final all = await repo.unlockAll();
    expect(all.length, 1);
    final c = all.first;
    expect(c.name, 'ZHANG SAN');
    expect(c.number, 'E12345678');
    expect(c.typeCode, 'HZ');
    expect(c.sex, '男');
    expect(c.nationalityCode, 'CHN');
    expect(c.expiryDate, '20300307');
    expect(c.source, CertSource.mrz);
    expect(c.personKey, 'p|ZHANG SAN|19900307');
  });

  test('存储中绝无明文（号码/姓名不可被直接 grep）', () async {
    final storage = _MemStorage();
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(1)),
      storage: storage,
    );
    await repo.save(cert);
    final raw = storage.db.values.join();
    expect(raw.contains('张三'), isFalse);
    expect(raw.contains('110101199003077758'), isFalse);
  });

  test('门禁拒绝 → 读/写/删/导出均抛 GateDeniedException（红队：无绕过）', () async {
    final repo = CertificateRepository(
      gate: const _FakeGate(false),
      keySource: _FixedKey(_k(0)),
      storage: _MemStorage(),
    );
    await expectLater(repo.save(cert), throwsA(isA<GateDeniedException>()));
    await expectLater(repo.unlockAll(), throwsA(isA<GateDeniedException>()));
    await expectLater(
        repo.deleteSecure('c1'), throwsA(isA<GateDeniedException>()));
    await expectLater(repo.exportEncrypted('password123'),
        throwsA(isA<GateDeniedException>()));
  });

  test('deleteSecure 过门禁后删除；密钥错误解密抛 FormatException', () async {
    final storage = _MemStorage();
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(0)),
      storage: storage,
    );
    await repo.save(cert);
    expect(storage.db.containsKey('c1'), isTrue);
    await repo.deleteSecure('c1');
    expect(storage.db.containsKey('c1'), isFalse);

    final k1 = CertificateCrypto(_k(0));
    final k2 = CertificateCrypto(_k(255));
    final payload = k1.encrypt(cert);
    expect(() => k2.decrypt(payload), throwsFormatException);
  });

  test('旧版加密数据（枚举 type）→ 自动迁移为 12306 代码', () {
    final key = _k(0);
    final legacyJson = jsonEncode(<String, dynamic>{
      'id': 'legacy1',
      'type': 'residentId',
      'number': '110101199003077758',
      'name': '旧数据',
      'birthDate': '19900307',
    });
    final payload = Sm4Cipher(Sm4Engine(key)).encryptStringToBase64(legacyJson);
    final cert = CertificateCrypto(key).decrypt(payload);
    expect(cert.typeCode, 'ED');
    expect(cert.name, '旧数据');
    expect(cert.birthDate, '19900307');
  });

  test('一人多证：同名同生日归并；同号不同人告警', () {
    const id = Certificate(
      id: 'a',
      typeCode: 'ED',
      number: '110101199003077758',
      name: '张三',
      birthDate: '19900307',
    );
    const passport = Certificate(
      id: 'b',
      typeCode: 'HZ',
      number: 'E12345678',
      name: '张三',
      birthDate: '19900307',
    );
    const other = Certificate(
      id: 'c',
      typeCode: 'ED',
      number: '440301199001012345',
      name: '李四',
      birthDate: '19900101',
    );
    final groups = groupCertificatesByPerson([id, passport, other]);
    expect(groups.length, 2);
    final zs = groups.firstWhere((g) => g.name == '张三');
    expect(zs.certCount, 2);
    expect(zs.birthDate, '19900307');

    // 同一号码挂到第二个"人"名下 → 告警
    const conflict = Certificate(
      id: 'd',
      typeCode: 'ED',
      number: '110101199003077758',
      name: 'ZHANG SAN',
      birthDate: '19900307',
    );
    final warns =
        duplicateCertificateNumberWarnings([id, passport, other, conflict]);
    expect(warns.length, 1);
    expect(warns.first, contains('张三'));
    expect(warns.first, contains('ZHANG SAN'));
  });

  test('口令信封导出→导入（跨设备）；错口令/坏文件拒绝；重复去重', () async {
    final src = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(0)),
      storage: _MemStorage(),
    );
    await src.save(cert);
    final envelope = await src.exportEncrypted('password123');

    // 信封元数据可见，密文内无明文
    final meta = jsonDecode(envelope) as Map<String, dynamic>;
    expect(meta['format'], 'railgo.cert.backup');
    expect(meta['v'], 2);
    // 审计 R-04：每次导出独立随机盐（防跨用户彩虹表预计算）
    expect(meta['salt'], isA<String>());
    expect(meta['salt'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(envelope.contains('张三'), isFalse);

    // 新设备（不同主密钥）凭口令导入
    final dst = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(7)),
      storage: _MemStorage(),
    );
    final r = await dst.importEncrypted('password123', envelope);
    expect(r.added, 1);
    final restored = await dst.unlockAll();
    expect(restored.first.name, '张三');
    expect(restored.first.typeCode, 'ED');

    // 再导入同一份 → 去重跳过
    final r2 = await dst.importEncrypted('password123', envelope);
    expect(r2.added, 0);
    expect(r2.skipped, 1);

    // 错口令
    await expectLater(
      dst.importEncrypted('wrongpass9', envelope),
      throwsA(isA<FormatException>()),
    );

    // 非备份文件
    await expectLater(
      dst.importEncrypted('password123', 'not-a-backup'),
      throwsA(isA<FormatException>()),
    );

    // 短口令直接拒绝
    await expectLater(
      src.exportEncrypted('short'),
      throwsA(isA<FormatException>()),
    );
  });

  test('旧 v1 固定盐信封可导入（向后兼容）', () async {
    // 手工构造旧格式信封（无 salt 字段，固定盐派生）
    final legacyKey =
        Sm4KeyService.deriveKeyFromPin('password123', salt: 'railgo.cert.backup.v1');
    final bundle = jsonEncode(<String, dynamic>{
      'v': 1,
      'certificates': [cert.toPlainJson()],
    });
    final payload =
        Sm4Cipher(Sm4Engine(legacyKey)).encryptStringToBase64(bundle);
    final legacyEnvelope = jsonEncode(<String, dynamic>{
      'format': 'railgo.cert.backup',
      'v': 1,
      'alg': 'SM4-CBC + PBKDF2-SHA256(100000)',
      'payload': payload,
    });

    final dst = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(9)),
      storage: _MemStorage(),
    );
    final r = await dst.importEncrypted('password123', legacyEnvelope);
    expect(r.added, 1);
    expect((await dst.unlockAll()).first.name, '张三');
  });

  test('损坏信封（payload 非字符串/缺失）→ FormatException 而非崩溃', () async {
    final repo = CertificateRepository(
      gate: const _FakeGate(true),
      keySource: _FixedKey(_k(0)),
      storage: _MemStorage(),
    );
    await expectLater(
      repo.importEncrypted(
          'password123', '{"format":"railgo.cert.backup","v":2,"payload":123}'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repo.importEncrypted(
          'password123', '{"format":"railgo.cert.backup","v":2}'),
      throwsA(isA<FormatException>()),
    );
  });
}
