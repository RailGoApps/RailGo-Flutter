// lib/core/security/key_service.dart
//
// SM4 密钥管理（任务书 §4.3 安全流程）：
//   1) 首次运行生成 128bit 随机密钥 → flutter_secure_storage（Keystore/Keychain 加密存储）
//   2) 读取安全存储失败（Keystore 损坏，如 Android 刷机/清凭证）→ 容灾：
//      以用户 PIN 经 PBKDF2(HMAC-SHA256, 10w轮) 派生密钥（应用内兜底加密）
//   3) 密钥仅存在内存与安全存储，绝不落明文盘（红队审查点）
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

abstract class Sm4KeySource {
  Future<Uint8List> obtain();
}

class SecureStorageKeyService implements Sm4KeySource {
  SecureStorageKeyService({FlutterSecureStorage? storage, this.pinFallback})
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true),
                iOptions: IOSOptions(
                    accessibility:
                        KeychainAccessibility.first_unlock_this_device));

  static const _kKeyEntry = 'railgo.sm4.master.key';

  final FlutterSecureStorage _storage;

  /// 可选 PIN 兜底（Keystore 损坏时使用）；null 则直接抛出
  final String? pinFallback;

  @override
  Future<Uint8List> obtain() async {
    try {
      final stored = await _storage.read(key: _kKeyEntry);
      if (stored != null && stored.length == 32) {
        return Sm4KeyService.hexToBytes(stored);
      }
      final fresh = _generateKey();
      await _storage.write(
          key: _kKeyEntry,
          value: fresh.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
      return fresh;
    } catch (_) {
      // 安全存储不可用（Keystore 损坏等）→ PIN 派生兜底
      if (pinFallback == null || pinFallback!.length < 4) {
        throw StateError('secure storage unavailable and no PIN fallback');
      }
      return Sm4KeyService.deriveKeyFromPin(pinFallback!);
    }
  }

  static Uint8List _generateKey() => Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  /// Zero-Trust 自检：探测安全存储读写（独立探测键，不触碰主密钥条目）。
  /// 用于证件页安全姿态面板判断"硬件级加密是否可用"。
  Future<bool> selfTest() async {
    const probeKey = 'railgo.sm4.probe';
    try {
      await _storage.write(key: probeKey, value: 'ok');
      final v = await _storage.read(key: probeKey);
      await _storage.delete(key: probeKey);
      return v == 'ok';
    } catch (_) {
      return false;
    }
  }
}

class Sm4KeyService {
  /// PBKDF2-HMAC-SHA256，100k 轮，盐固定为应用域分隔符+PIN（PIN 即口令，无独立盐存储需求）
  static Uint8List deriveKeyFromPin(
    String pin, {
    int iterations = 100000,
    String salt = 'railgo.sm4.pin.v1',
  }) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
        utf8.encode(salt),
        iterations,
        16,
      ));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static Uint8List hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
