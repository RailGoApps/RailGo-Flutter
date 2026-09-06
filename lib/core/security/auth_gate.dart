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

/// PIN 哈希（纯逻辑，可单测）：SHA-256(salt+pin) 迭代 5000 轮。
class PinHasher {
  const PinHasher();

  static bool isValidPinFormat(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  String hash(String pin, String salt) {
    var bytes = Uint8List.fromList(utf8.encode(salt + pin));
    final d = SHA256Digest();
    for (var i = 0; i < 5000; i++) {
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
  LocalAuthGate({LocalAuthentication? localAuth, SharedPreferences? prefs, PinHasher? hasher})
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
    final ok = _hasher.fixedTimeEquals(_hasher.hash(input, salt), stored);
    return GateResult(passed: ok, method: ok ? GateMethod.pin : GateMethod.denied);
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
    return prefs.setString(_kPinHash, _hasher.hash(pin, salt));
  }

  @override
  Future<void> clearPin() async {
    await _prefs?.remove(_kPinHash);
    await _prefs?.remove(_kPinSalt);
  }
}
