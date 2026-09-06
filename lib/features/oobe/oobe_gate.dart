// lib/features/oobe/oobe_gate.dart
//
// OOBE 门禁（基线 App.vue onLaunch 移植）：
//   oobe 未完成 → welcome；完成但 15 项服务源有缺 → 强拦服务源配置页。
//   逻辑纯函数化（可单测），UI 导航由壳层消费结果。
library;

import '../../core/network/service_registry.dart';
import '../../core/storage/settings_store.dart';

enum OobeRoute { welcome, serviceSource, home }

OobeRoute resolveOobeRoute(SettingsStore settings) {
  if (!settings.oobeDone) return OobeRoute.welcome;
  for (final code in ServiceCode.all) {
    final src = settings.serviceSource(code);
    if (src == null || src.isEmpty) return OobeRoute.serviceSource;
  }
  return OobeRoute.home;
}

/// 全部服务源已配置？（设置页/OOBE 共用）
bool allServiceSourcesConfigured(SettingsStore settings) =>
    resolveOobeRoute(settings) == OobeRoute.home;
