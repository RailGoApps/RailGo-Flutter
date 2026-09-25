// 设置存储：缺省值 / 钳制 / 服务源透传（mock prefs 纯单测）
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('缺省值：在线模式 / 换乘 18h / OOBE 未完成 / 无 locale / 需授权关',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = SharedPreferencesSettingsStore(await SharedPreferences.getInstance());
    expect(s.mode, AppMode.network);
    expect(s.maxTransferHours, 18);
    expect(s.oobeDone, isFalse);
    expect(s.localeOverride, '');
    expect(s.needAuth, isFalse);
    expect(s.serviceSource('train'), isNull);
  });

  test('最大换乘时间钳制在 [1, 24]', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SharedPreferencesSettingsStore(prefs);
    await s.setMaxTransferHours(0);
    expect(s.maxTransferHours, 1);
    await s.setMaxTransferHours(99);
    expect(s.maxTransferHours, 24);
    await s.setMaxTransferHours(8);
    expect(s.maxTransferHours, 8);
    // 落盘的原始值也已被钳制（防绕过 getter 直接读 prefs）
    expect(prefs.getInt('maxTransferHours'), 8);
  });

  test('脏数据钳制：越界原始值读取时收敛', () async {
    SharedPreferences.setMockInitialValues({'maxTransferHours': 99});
    final s = SharedPreferencesSettingsStore(await SharedPreferences.getInstance());
    expect(s.maxTransferHours, 24);
  });

  test('服务源与模式读写往返', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SharedPreferencesSettingsStore(prefs);
    await s.setServiceSource('train', 'https://mirror.example');
    expect(s.serviceSource('train'), 'https://mirror.example');
    await s.setMode(AppMode.local);
    expect(s.mode, AppMode.local);
    await s.setOobeDone(true);
    expect(s.oobeDone, isTrue);
    await s.setLocaleOverride('zh_HK');
    expect(s.localeOverride, 'zh_HK');
    await s.setNeedAuth(true);
    expect(s.needAuth, isTrue);
  });
}
