// test/features/oobe/oobe_gate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/network/service_registry.dart';
import 'package:railgo/core/storage/settings_store.dart';
import 'package:railgo/features/oobe/oobe_gate.dart';

class _FakeSettings implements SettingsStore {
  _FakeSettings({this.oobe = false, this.sources = const {}});
  bool oobe;
  final Map<String, String> sources;

  @override
  String? serviceSource(String code) => sources[code];
  @override
  Future<void> setServiceSource(String code, String url) async => sources[code] = url;
  @override
  AppMode get mode => AppMode.network;
  @override
  Future<void> setMode(AppMode mode) async {}
  @override
  int get maxTransferHours => 18;
  @override
  Future<void> setMaxTransferHours(int hours) async {}
  @override
  bool get oobeDone => oobe;
  @override
  Future<void> setOobeDone(bool done) async => oobe = done;
  @override
  String get localeOverride => '';
  @override
  Future<void> setLocaleOverride(String locale) async {}
  @override
  bool get needAuth => false;
  @override
  Future<void> setNeedAuth(bool v) async {}
}

void main() {
  test('oobe 未完成 → welcome', () {
    expect(resolveOobeRoute(_FakeSettings(oobe: false)), OobeRoute.welcome);
  });

  test('oobe 完成但服务源缺失 → serviceSource', () {
    final s = _FakeSettings(oobe: true, sources: {ServiceCode.train: 'https://a'});
    expect(resolveOobeRoute(s), OobeRoute.serviceSource);
  });

  test('15 项服务源齐备 → home', () {
    final s = _FakeSettings(
      oobe: true,
      sources: {for (final c in ServiceCode.all) c: 'https://svc/$c'},
    );
    expect(resolveOobeRoute(s), OobeRoute.home);
    expect(allServiceSourcesConfigured(s), isTrue);
  });

  test('任一服务源为空串视为缺失', () {
    final map = {for (final c in ServiceCode.all) c: 'https://svc/$c'};
    map[ServiceCode.tp] = '';
    expect(resolveOobeRoute(_FakeSettings(oobe: true, sources: map)), OobeRoute.serviceSource);
  });
}
