// lib/core/storage/settings_store.dart
//
// 设置存储（对应原项目 uni storage 键位体系的 Flutter 重构，基线 §4.5）。
// 接口抽象 + 逻辑（缺省值/钳制）与插件实现分离，便于纯单测。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 使用模式（基线 about/mode.vue：network / local；ol 仅离线已禁用）
enum AppMode { network, local }

abstract class SettingsStore {
  String? serviceSource(String code);
  Future<void> setServiceSource(String code, String url);
  AppMode get mode;
  Future<void> setMode(AppMode mode);
  int get maxTransferHours;
  Future<void> setMaxTransferHours(int hours);
  bool get oobeDone;
  Future<void> setOobeDone(bool done);
  String get localeOverride; // '' = 跟随系统
  Future<void> setLocaleOverride(String locale);
  bool get needAuth;
  Future<void> setNeedAuth(bool v);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? serviceSource(String code) => _prefs.getString('service_source_$code');

  @override
  Future<void> setServiceSource(String code, String url) =>
      _prefs.setString('service_source_$code', url);

  @override
  AppMode get mode {
    final v = _prefs.getString('mode');
    return v == 'local' ? AppMode.local : AppMode.network;
  }

  @override
  Future<void> setMode(AppMode mode) => _prefs.setString('mode', mode.name);

  @override
  int get maxTransferHours {
    final v = _prefs.getInt('maxTransferHours') ?? 18;
    if (v < 1) return 1;
    if (v > 24) return 24;
    return v;
  }

  @override
  Future<void> setMaxTransferHours(int hours) async {
    final clamped = hours < 1 ? 1 : (hours > 24 ? 24 : hours);
    await _prefs.setInt('maxTransferHours', clamped);
  }

  @override
  bool get oobeDone => _prefs.getBool('oobe') ?? false;

  @override
  Future<void> setOobeDone(bool done) => _prefs.setBool('oobe', done);

  @override
  String get localeOverride => _prefs.getString('localeOverride') ?? '';

  @override
  Future<void> setLocaleOverride(String locale) => _prefs.setString('localeOverride', locale);

  @override
  bool get needAuth => _prefs.getBool('NeedAuth') ?? false;

  @override
  Future<void> setNeedAuth(bool v) => _prefs.setBool('NeedAuth', v);
}
