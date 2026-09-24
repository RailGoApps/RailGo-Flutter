// lib/core/security/auth_gate.dart
//
// Passkey 门禁（任务书 §4.3）：
//   读写证件前必须通过生物识别（local_auth）；不可用/失败 → 6 位数字 PIN。
//   红队审查点：任何敏感操作必须消费 [GateResult.passed == true] 的返回值，
//   严禁"触发弹窗后不看结果直接放行"。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GateMethod { biometric, pin, denied }

class GateResult {
  const GateResult({required this.passed, required this.method});
  final bool passed;
  final GateMethod method;
}

/// PIN 哈希（纯逻辑，可单测）：SHA-256(salt+pin) 多轮迭代。
class PinHasher {
  const PinHasher();

  /// 旧版 5000 轮（仅用于校验历史数据并触发透明升级）
  static const int kLegacyIterations = 5000;

  /// 当前 100k 轮（与密钥派生同量级；纯 Dart 移动端 <1s，PIN 属低频路径）
  static const int kCurrentIterations = 100000;

  static bool isValidPinFormat(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  String hash(String pin, String salt, {int iterations = kLegacyIterations}) {
    var bytes = Uint8List.fromList(utf8.encode(salt + pin));
    final d = SHA256Digest();
    for (var i = 0; i < iterations; i++) {
      bytes = d.process(bytes);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 恒时比较（防时序侧信道）
  bool fixedTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  String randomSaltHex() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

abstract class AuthGate {
  Future<GateResult> requireUnlock({String reason});
  Future<GateResult> verifyPin(String input);
  Future<bool> setupPin(String pin);
  Future<void> clearPin();
  bool get hasPin;
}

class LocalAuthGate implements AuthGate {
  LocalAuthGate(
      {LocalAuthentication? localAuth,
      SharedPreferences? prefs,
      PinHasher? hasher})
      : _la = localAuth ?? LocalAuthentication(),
        _prefs = prefs,
        _hasher = hasher ?? const PinHasher();

  static const _kPinHash = 'railgo.pin.hash';
  static const _kPinSalt = 'railgo.pin.salt';

  final LocalAuthentication _la;
  final SharedPreferences? _prefs;
  final PinHasher _hasher;

  @override
  bool get hasPin => _prefs?.getString(_kPinHash) != null;

  @override
  Future<GateResult> requireUnlock({String reason = '访问加密证件'}) async {
    try {
      final can = await _la.canCheckBiometrics || await _la.isDeviceSupported();
      if (can) {
        final ok = await _la.authenticate(localizedReason: reason);
        if (ok) {
          return const GateResult(passed: true, method: GateMethod.biometric);
        }
        // 生物识别失败 → 返回 denied，由 UI 走 PIN 收集 → verifyPin
      }
    } catch (_) {
      // 生物识别异常（无权限/无硬件/用户取消）→ PIN 路径
    }
    return const GateResult(passed: false, method: GateMethod.denied);
  }

  @override
  Future<GateResult> verifyPin(String input) async {
    final stored = _prefs?.getString(_kPinHash);
    final salt = _prefs?.getString(_kPinSalt);
    if (stored == null || salt == null) {
      return const GateResult(passed: false, method: GateMethod.denied);
    }
    final bool ok;
    if (stored.startsWith('v2:')) {
      ok = _hasher.fixedTimeEquals(
        _hasher.hash(input, salt, iterations: PinHasher.kCurrentIterations),
        stored.substring(3),
      );
    } else {
      // 旧 5000 轮哈希：校验通过即透明升级为 v2（用户无感）
      ok = _hasher.fixedTimeEquals(_hasher.hash(input, salt), stored);
      if (ok) {
        await _prefs?.setString(
          _kPinHash,
          'v2:${_hasher.hash(input, salt, iterations: PinHasher.kCurrentIterations)}',
        );
      }
    }
    return GateResult(
        passed: ok, method: ok ? GateMethod.pin : GateMethod.denied);
  }

  @override
  Future<bool> setupPin(String pin) {
    if (!PinHasher.isValidPinFormat(pin)) return Future.value(false);
    return _doSetup(pin);
  }

  Future<bool> _doSetup(String pin) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final salt = _hasher.randomSaltHex();
    final ok = await prefs.setString(_kPinSalt, salt);
    if (!ok) return false;
    return prefs.setString(
      _kPinHash,
      'v2:${_hasher.hash(pin, salt, iterations: PinHasher.kCurrentIterations)}',
    );
  }

  @override
  Future<void> clearPin() async {
    await _prefs?.remove(_kPinHash);
    await _prefs?.remove(_kPinSalt);
  }

  /// 设备上可用的生物识别通行令牌（面容/指纹/虹膜/强弱生物识别）。
  /// 按名称字符串比较，兼容各平台 local_auth 枚举成员差异。
  Future<List<String>> biometricKinds() async {
    try {
      final kinds = await _la.getAvailableBiometrics();
      return kinds.map(_describeBiometric).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static String _describeBiometric(BiometricType t) {
    final n = t.name;
    if (n == 'face') return '面容';
    if (n == 'fingerprint') return '指纹';
    if (n == 'iris') return '虹膜';
    if (n == 'strong') return '强生物识别';
    if (n == 'weak') return '弱生物识别';
    return n;
  }
}

/// 会话级门禁：授权一次后会话内放行（页面持有；离开页面或手动上锁即失效）。
/// 目的：一次生物识别覆盖"读/写/删/导出"，同时保证任何路径都先过门禁——
/// 红队规则不变：所有敏感操作必须消费 [GateResult.passed == true]。
class SessionAuthGate implements AuthGate {
  SessionAuthGate(this._inner);

  final AuthGate _inner;
  bool _passed = false;

  bool get unlocked => _passed;

  void lock() => _passed = false;

  @override
  bool get hasPin => _inner.hasPin;

  @override
  Future<GateResult> requireUnlock({String reason = '访问加密证件'}) async {
    if (_passed) {
      return const GateResult(passed: true, method: GateMethod.biometric);
    }
    final r = await _inner.requireUnlock(reason: reason);
    if (r.passed) _passed = true;
    return r;
  }

  @override
  Future<GateResult> verifyPin(String input) async {
    if (_passed) {
      return const GateResult(passed: true, method: GateMethod.pin);
    }
    final r = await _inner.verifyPin(input);
    if (r.passed) _passed = true;
    return r;
  }

  @override
  Future<bool> setupPin(String pin) => _inner.setupPin(pin);

  @override
  Future<void> clearPin() async {
    _passed = false;
    await _inner.clearPin();
  }
}
