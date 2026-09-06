// lib/features/certificate/certificate_repository.dart
//
// 证件管理（任务书 §4.3，原项目无此功能——Baseline §0/#3）：
//   字段：证件类型(必)/号码(必)/姓名(必)/电话/邮箱/出生日期(必)/图像(可选)
//   流程：任何读写必须先过 AuthGate（生物识别→PIN）；数据 JSON→SM4(CBC)→Base64 落库；
//   密钥仅经 SecureStorageKeyService（Keystore 损坏时 PIN 派生兜底）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/sm4.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/key_service.dart';

enum CertType { residentId, passport, hkmTravelPermit, twTravelPermit, other }

class Certificate {
  const Certificate({
    required this.id,
    required this.type,
    required this.number,
    required this.name,
    this.phone,
    this.email,
    required this.birthDate,
    this.imageBase64,
    this.encryptedPayload,
  });

  final String id;
  final CertType type;
  final String number;
  final String name;
  final String? phone;
  final String? email;

  /// yyyymmdd
  final String birthDate;

  /// 证件图像（明文仅存在于解锁后的内存；入库前整体加密）
  final String? imageBase64;

  /// 加密态（Base64(SM4-CBC(IV+JSON))）；解密态时为 null
  final String? encryptedPayload;

  Map<String, dynamic> toPlainJson() => {
        'id': id,
        'type': type.name,
        'number': number,
        'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'birthDate': birthDate,
        if (imageBase64 != null) 'image': imageBase64,
      };
}

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
    return Certificate(
      id: plain['id'] as String,
      type: CertType.values.firstWhere(
        (t) => t.name == plain['type'],
        orElse: () => CertType.other,
      ),
      number: plain['number'] as String,
      name: plain['name'] as String,
      phone: plain['phone'] as String?,
      email: plain['email'] as String?,
      birthDate: plain['birthDate'] as String,
      imageBase64: plain['image'] as String?,
    );
  }
}

/// 仓储门面：强制"先门禁后读写"（红队：不允许绕过 Gate 直接解密）
class CertificateRepository {
  CertificateRepository({
    required this.gate,
    required this.keySource,
    required this.storage,
  });

  final AuthGate gate;
  final Sm4KeySource keySource;
  final CertificateStorage storage;

  /// 解锁并返回全部证件明文（触发一次门禁）
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

  Future<void> delete(String id) => storage.remove(id);
}

class GateDeniedException implements Exception {
  const GateDeniedException();
  @override
  String toString() => 'GateDeniedException: 生物识别/PIN 未通过，拒绝访问证件';
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
      return <String, String>{}; // 损坏 → 空（容灾）
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
