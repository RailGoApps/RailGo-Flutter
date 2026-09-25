// 密钥服务：自检 / 生成与复用 / Keystore 损坏时的 PIN 派生兜底
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/key_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({this.broken = false});

  /// true = 模拟 Keystore/Keychain 损坏（读写均抛错）
  final bool broken;
  final Map<String, String> db = {};

  void _check() {
    if (broken) throw StateError('secure storage unavailable');
  }

  @override
  Future<void> write({
    required String key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    if (value == null) {
      db.remove(key);
    } else {
      db[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    return db[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    db.remove(key);
  }
}

void main() {
  test('selfTest：安全存储可读写 → true，探测键清理', () async {
    final storage = _FakeSecureStorage();
    final svc = SecureStorageKeyService(storage: storage);
    expect(await svc.selfTest(), isTrue);
    expect(storage.db.containsKey('railgo.sm4.probe'), isFalse);
  });

  test('selfTest：Keystore 损坏 → false（姿态面板据此降级）', () async {
    final svc = SecureStorageKeyService(storage: _FakeSecureStorage(broken: true));
    expect(await svc.selfTest(), isFalse);
  });

  test('obtain：首次生成 128bit 密钥并持久化；二次读取复用同一密钥', () async {
    final storage = _FakeSecureStorage();
    final svc = SecureStorageKeyService(storage: storage);
    final k1 = await svc.obtain();
    final k2 = await svc.obtain();
    expect(k1.length, 16);
    expect(k2, k1);
    final stored = storage.db['railgo.sm4.master.key'];
    expect(stored, isNotNull);
    expect(stored!.length, 32); // hex
    expect(Sm4KeyService.hexToBytes(stored), k1);
  });

  test('obtain：安全存储损坏且无 PIN 兜底 → 显式失败（不做空密钥假象）',
      () async {
    final svc =
        SecureStorageKeyService(storage: _FakeSecureStorage(broken: true));
    expect(svc.obtain(), throwsStateError);
  });

  test('obtain：安全存储损坏但有 PIN → PBKDF2 确定性派生（灾备路径）',
      () async {
    final svc = SecureStorageKeyService(
      storage: _FakeSecureStorage(broken: true),
      pinFallback: '123456',
    );
    final k = await svc.obtain();
    expect(k, Sm4KeyService.deriveKeyFromPin('123456'));
  });
}
