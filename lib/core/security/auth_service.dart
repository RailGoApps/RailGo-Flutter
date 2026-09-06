// lib/core/security/auth_service.dart
//
// 卡密鉴权服务（基线 App.vue check() 移植 + 72h 离线宽限）：
//   成功 → 记录 AuthTime；网络失败且距上次成功 < 72h → 放行"离线鉴权"；
//   ≥72h 或服务端判 invalid → 要求重新鉴权（OOBE auth 页）。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/railgo_api.dart';

class AuthService {
  AuthService({required RailGoApi api, SharedPreferences? prefs})
      : _api = api,
        _prefs = prefs;

  static const _kAuthTime = 'AuthTime';
  static const _kJqok = 'jqok';
  static const _kLastResult = 'auth.last.result';
  static const offlineGrace = Duration(hours: 72);

  final RailGoApi _api;
  final SharedPreferences? _prefs;

  DateTime? get lastAuthTime {
    final ms = _prefs?.getInt(_kAuthTime);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get isAuthed => _prefs?.getBool(_kJqok) ?? false;

  Future<AuthCheckResult> check({required String version, required String userid, required String key}) async {
    try {
      final resp = await _api.checkAuth(version: version, userid: userid, key: key);
      final data = resp.data;
      final valid = data != null && data['valid'] == true;
      if (valid) {
        await _prefs?.setInt(_kAuthTime, DateTime.now().millisecondsSinceEpoch);
        await _prefs?.setBool(_kJqok, true);
      } else {
        await _prefs?.setBool(_kJqok, false);
      }
      await _prefs?.setString(_kLastResult, valid ? 'ok' : 'invalid');
      return AuthCheckResult(valid, AuthSource.remote);
    } on Exception {
      // 网络异常 → 72h 宽限判定
      final last = lastAuthTime;
      if (last != null && DateTime.now().difference(last) < offlineGrace) {
        return AuthCheckResult(true, AuthSource.graceOffline);
      }
      return AuthCheckResult(false, AuthSource.networkError);
    }
  }

  /// 纯函数：宽限判定（单测用）
  static bool withinGrace(DateTime? lastAuth, DateTime now) =>
      lastAuth != null && now.difference(lastAuth) < offlineGrace;
}

enum AuthSource { remote, graceOffline, networkError }

class AuthCheckResult {
  const AuthCheckResult(this.valid, this.source);
  final bool valid;
  final AuthSource source;
}
