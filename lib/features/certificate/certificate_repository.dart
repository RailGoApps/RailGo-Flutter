// lib/features/certificate/certificate_repository.dart
//
// 证件管理 v2（任务书 §4.3，原项目无此功能——Baseline §0/#3）：
//   模型：12306 证件代码 + 号码/MRZ 识读字段 + 一人多证 personKey；
//   流程：任何读写删导出必须先过 AuthGate（面容/指纹→PIN）；
//   落库：JSON→SM4-CBC→Base64；密钥仅经 SecureStorageKeyService
//         （Keystore 损坏时 PIN 派生兜底）。
//   导出：TEE 密钥不可导出 → 口令信封（PBKDF2→SM4）跨设备迁移。
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/sm4.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/key_service.dart';
import 'certificate_types.dart';
import 'id_number.dart';
import 'mrz.dart';

enum CertSource { manual, mrz }

class Certificate {
  const Certificate({
    required this.id,
    required this.typeCode,
    required this.number,
    required this.name,
    this.phone,
    this.email,
    this.birthDate,
    this.sex,
    this.nationalityCode,
    this.nationality,
    this.expiryDate,
    this.source = CertSource.manual,
    this.encryptedPayload,
  });

  final String id;

  /// 12306 两字母证件码（ED/HZ/GN/…）
  final String typeCode;
  final String number;
  final String name;
  final String? phone;
  final String? email;

  /// yyyymmdd；可由号码识读或 MRZ 提取
  final String? birthDate;

  /// 男 / 女 / null
  final String? sex;
  final String? nationalityCode;
  final String? nationality;

  /// yyyymmdd
  final String? expiryDate;
  final CertSource source;

  /// 加密态（Base64(SM4-CBC(IV+JSON))）；解密态时为 null
  final String? encryptedPayload;

  /// 一人多证归并键：同名同生日视为同一人；
  /// 生日缺失时退化为 姓名+号码（宁可漏合并，不可误合并陌生人）。
  String get personKey => certPersonKey(name, birthDate, number);

  Map<String, dynamic> toPlainJson() => {
        'id': id,
        'typeCode': typeCode,
        'number': number,
        'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (birthDate != null) 'birthDate': birthDate,
        if (sex != null) 'sex': sex,
        if (nationalityCode != null) 'nationalityCode': nationalityCode,
        if (nationality != null) 'nationality': nationality,
        if (expiryDate != null) 'expiryDate': expiryDate,
        'source': source.name,
      };

  factory Certificate.fromPlainJson(Map<String, dynamic> j) => Certificate(
        id: j['id'] as String,
        typeCode: normalizeTypeCode(j['typeCode'] ?? j['type']),
        number: j['number'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        birthDate: _blankToNull(j['birthDate'] as String?),
        sex: _blankToNull(j['sex'] as String?),
        nationalityCode: _blankToNull(j['nationalityCode'] as String?),
        nationality: _blankToNull(j['nationality'] as String?),
        expiryDate: _blankToNull(j['expiryDate'] as String?),
        source: j['source'] == 'mrz' ? CertSource.mrz : CertSource.manual,
      );

  factory Certificate.fromMrz(MrzResult mrz, {required String id}) =>
      Certificate(
        id: id,
        typeCode: mrz.certTypeCode,
        number: mrz.documentNumber,
        name: mrz.fullName,
        birthDate: mrz.birthDate,
        sex: mrz.sex == CertGender.unknown ? null : certGenderLabel(mrz.sex),
        nationalityCode: mrz.nationalityCode,
        nationality: mrz.nationalityName,
        expiryDate: mrz.expiryDate,
        source: CertSource.mrz,
      );

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

String certPersonKey(String name, String? birthDate, String number) {
  final n = name.trim();
  final b = birthDate?.trim() ?? '';
  return b.length == 8 ? 'p|$n|$b' : 'n|$n|${number.trim()}';
}

/// 一人多证分组
class PersonGroup {
  const PersonGroup({
    required this.key,
    required this.name,
    this.birthDate,
    required this.certificates,
  });

  final String key;
  final String name;
  final String? birthDate;
  final List<Certificate> certificates;

  int get certCount => certificates.length;
}

List<PersonGroup> groupCertificatesByPerson(Iterable<Certificate> certs) {
  final map = <String, List<Certificate>>{};
  for (final c in certs) {
    map.putIfAbsent(c.personKey, () => []).add(c);
  }
  final groups = <PersonGroup>[];
  for (final e in map.entries) {
    String? birth;
    for (final c in e.value) {
      final b = c.birthDate;
      if (b != null && b.length == 8) {
        birth = b;
        break;
      }
    }
    groups.add(PersonGroup(
      key: e.key,
      name: e.value.first.name,
      birthDate: birth,
      certificates: e.value,
    ));
  }
  groups.sort((a, b) {
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.key.compareTo(b.key);
  });
  return groups;
}

/// 同一号码出现在多个"人"名下 → 告警（多半是中英文姓名/生日口径不一致导致漏合并）
List<String> duplicateCertificateNumberWarnings(Iterable<Certificate> certs) {
  final byNumber = <String, Set<String>>{};
  for (final c in certs) {
    final num = c.number.trim().toUpperCase();
    if (num.isEmpty) continue;
    byNumber.putIfAbsent(num, () => {}).add(c.personKey);
  }
  final out = <String>[];
  for (final e in byNumber.entries) {
    if (e.value.length > 1) {
      final names = e.value.map((k) => k.split('|')[1]).toSet().join('、');
      out.add('证件号 ${_maskNumber(e.key)} 同时挂在 $names 名下，请核对是否同一人');
    }
  }
  return out;
}

String _maskNumber(String n) =>
    n.length <= 4 ? n : '${n.substring(0, 2)}****${n.substring(n.length - 2)}';

/// 纯加解密（无 IO，可单测）：Certificate ⇄ 加密 Base64 载荷
class CertificateCrypto {
  const CertificateCrypto(this._keyBytes);

  final List<int> _keyBytes;

  String encrypt(Certificate c) {
    final cipher = Sm4Cipher(Sm4Engine(_keyBytes));
    return cipher.encryptStringToBase64(jsonEncode(c.toPlainJson()));
  }

  Certificate decrypt(String payload) {
    final cipher = Sm4Cipher(Sm4Engine(_keyBytes));
    final plain = jsonDecode(cipher.decryptStringFromBase64(payload))
        as Map<String, dynamic>;
    return Certificate.fromPlainJson(plain);
  }
}

/// 仓储门面：强制"先门禁后读写删导出"（红队：不允许绕过 Gate 直接操作密文）
class CertificateRepository {
  CertificateRepository({
    required this.gate,
    required this.keySource,
    required this.storage,
  });

  final AuthGate gate;
  final Sm4KeySource keySource;
  final CertificateStorage storage;

  /// 换门禁视图（页面用 SessionAuthGate 包一层，实现"一次授权全会话"）
  CertificateRepository withGate(AuthGate newGate) => CertificateRepository(
        gate: newGate,
        keySource: keySource,
        storage: storage,
      );

  Future<List<Certificate>> unlockAll() async {
    final g = await gate.requireUnlock(reason: '查看加密证件');
    if (!g.passed) {
      throw const GateDeniedException();
    }
    final key = await keySource.obtain();
    final crypto = CertificateCrypto(key);
    final payloads = await storage.loadAll();
    return payloads.map(crypto.decrypt).toList(growable: false);
  }

  /// 新增/编辑证件（触发门禁；成功后以密文落库）
  Future<void> save(Certificate plain) async {
    final g = await gate.requireUnlock(reason: '编辑加密证件');
    if (!g.passed) {
      throw const GateDeniedException();
    }
    final key = await keySource.obtain();
    final crypto = CertificateCrypto(key);
    await storage.store(plain.id, crypto.encrypt(plain));
  }

  /// 删除也必须过门禁（红队补洞：旧版 delete 无验证即可删密文记录）
  Future<void> deleteSecure(String id) async {
    final g = await gate.requireUnlock(reason: '删除加密证件');
    if (!g.passed) {
      throw const GateDeniedException();
    }
    await storage.remove(id);
  }

  // ─────────────── 导出 / 导入（口令信封） ───────────────
  //
  // 设备 SM4 主密钥在 TEE/Keystore 内不可导出 → 跨设备迁移必须有可携带秘密。
  // 方案：导出口令 --PBKDF2(100k, 独立盐域)--> 信封密钥 --SM4--> 密文体。
  // 明文仅出现在授权后的内存；信封内不含设备密钥与 PIN。

  Future<String> exportEncrypted(String passphrase) async {
    _requirePassphrase(passphrase);
    final g = await gate.requireUnlock(reason: '导出加密证件');
    if (!g.passed) {
      throw const GateDeniedException();
    }
    final certs = await unlockAll(); // 会话门禁下二次调用免重复验证
    final bundle = <String, dynamic>{
      'v': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'persons': [
        for (final p in groupCertificatesByPerson(certs))
          {
            'name': p.name,
            if (p.birthDate != null) 'birthDate': p.birthDate,
          },
      ],
      'certificates': [for (final c in certs) c.toPlainJson()],
    };
    // 审计 R-04：每次导出使用独立随机盐（防跨用户彩虹表预计算）
    final salt = _randomSaltHex();
    final cipher = Sm4Cipher(Sm4Engine(_backupKey(passphrase, saltHex: salt)));
    return jsonEncode(<String, dynamic>{
      'format': 'railgo.cert.backup',
      'v': 2,
      'alg': 'SM4-CBC + PBKDF2-SHA256(100000)',
      'salt': salt,
      'payload': cipher.encryptStringToBase64(jsonEncode(bundle)),
    });
  }

  Future<CertImportResult> importEncrypted(
    String passphrase,
    String envelope, {
    bool merge = true,
  }) async {
    _requirePassphrase(passphrase);
    final g = await gate.requireUnlock(reason: '导入加密证件');
    if (!g.passed) {
      throw const GateDeniedException();
    }
    final decoded = jsonDecode(envelope);
    if (decoded is! Map ||
        decoded['format'] != 'railgo.cert.backup') {
      throw const FormatException('不是 RailGo 证件备份文件');
    }
    // 审计 B-02 同类加固：字段类型先验后用，坏文件统一 FormatException
    final payload = decoded['payload'];
    if (payload is! String || payload.isEmpty) {
      throw const FormatException('备份文件损坏（payload 缺失）');
    }
    // v2 信封带随机盐；v1 旧信封回退固定盐（向后兼容）
    final saltField = decoded['salt'];
    final saltHex = saltField is String &&
            RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(saltField)
        ? saltField
        : kLegacyBackupSalt;
    final cipher = Sm4Cipher(Sm4Engine(_backupKey(passphrase, saltHex: saltHex)));
    final Object bundleRaw;
    try {
      bundleRaw = jsonDecode(cipher.decryptStringFromBase64(payload));
    } on FormatException {
      throw const FormatException('口令错误或备份损坏');
    }
    if (bundleRaw is! Map<String, dynamic>) {
      throw const FormatException('备份文件损坏（内容结构异常）');
    }
    final bundle = bundleRaw;
    final list = bundle['certificates'];
    if (list is! List) {
      throw const FormatException('备份文件损坏（certificates 缺失）');
    }
    final incoming = <Certificate>[];
    for (final e in list) {
      incoming.add(Certificate.fromPlainJson(e as Map<String, dynamic>));
    }
    final existing = await unlockAll(); // 会话门禁下免重复验证
    final existIds = existing.map((c) => c.id).toSet();
    final existNums = existing.map((c) => '${c.typeCode}/${c.number}').toSet();
    var added = 0;
    var skipped = 0;
    for (final c in incoming) {
      final dup = merge &&
          (existIds.contains(c.id) ||
              existNums.contains('${c.typeCode}/${c.number}'));
      if (dup) {
        skipped++;
        continue;
      }
      await save(c); // 会话门禁下免重复验证
      added++;
    }
    return CertImportResult(added: added, skipped: skipped);
  }

  static void _requirePassphrase(String passphrase) {
    if (passphrase.length < 8) {
      throw const FormatException('导出口令至少 8 位');
    }
  }

  /// v1 固定盐（仅用于导入旧信封；新导出不再使用）
  static const String kLegacyBackupSalt = 'railgo.cert.backup.v1';

  static List<int> _backupKey(String passphrase, {String? saltHex}) =>
      Sm4KeyService.deriveKeyFromPin(
        passphrase,
        salt: saltHex ?? kLegacyBackupSalt,
      );

  static String _randomSaltHex() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class CertImportResult {
  const CertImportResult({required this.added, required this.skipped});

  final int added;
  final int skipped;
}

class GateDeniedException implements Exception {
  const GateDeniedException();

  @override
  String toString() => 'GateDeniedException: 通行密钥未授权，拒绝访问证件';
}

/// 存储接口（实现A：sqflite 表 certificates(id TEXT PK, payload TEXT)；实现B：Prefs JSON）
abstract class CertificateStorage {
  Future<List<String>> loadAll();

  Future<void> store(String id, String encryptedPayload);

  Future<void> remove(String id);
}

/// shared_preferences 实现（密文 JSON map；与 SQLite 实现可替换）
class PrefsCertificateStorage implements CertificateStorage {
  PrefsCertificateStorage(this._prefs);

  final SharedPreferences _prefs;
  static const _kKey = 'railgo.certificates.v1';

  Future<Map<String, String>> _read() async {
    try {
      final raw = _prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // 审计 B-02：损坏数据先隔离留档，防止下次 store() 覆盖后无从恢复
      final raw = _prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        await _prefs.setString(
            '$_kKey.corrupt.${DateTime.now().millisecondsSinceEpoch}', raw);
      }
      return <String, String>{}; // 当前会话视为空库（容灾）
    }
  }

  @override
  Future<List<String>> loadAll() async => (await _read()).values.toList();

  @override
  Future<void> store(String id, String encryptedPayload) async {
    final m = await _read();
    m[id] = encryptedPayload;
    await _prefs.setString(_kKey, jsonEncode(m));
  }

  @override
  Future<void> remove(String id) async {
    final m = await _read();
    m.remove(id);
    await _prefs.setString(_kKey, jsonEncode(m));
  }
}
