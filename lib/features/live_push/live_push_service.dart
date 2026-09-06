// lib/features/live_push/live_push_service.dart
//
// Live-Push 实时活动（任务书 §4.4，原项目仅一个未被调用的 Android AppWidget——Baseline §0）：
//   iOS: ActivityKit+WidgetKit（灵动岛/锁屏）｜Android: 前台服务通知｜HarmonyOS: 实况窗
//   全部经 PlatformChannel 抽象；通道不可用 → flutter_local_notifications 兜底。
//   内容：状态/车次号/下一站/预计到发/换乘倒计时；本地定时器驱动，不依赖网络。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LivePushContent {
  const LivePushContent({
    required this.stateLabel,
    required this.trainNum,
    this.nextStation,
    this.etaText,
    this.transferCountdownText,
  });

  final String stateLabel; // 即将出发/下一站/正在停靠/即将到达
  final String trainNum;
  final String? nextStation;
  final String? etaText;
  final String? transferCountdownText;
}

abstract class LivePushBackend {
  Future<bool> isAvailable();
  Future<void> start(String tripId, LivePushContent initial);
  Future<void> update(String tripId, LivePushContent content);
  Future<void> stop(String tripId);
}

/// 本地通知兜底（三端皆可用；低刷新频率全量更新）
class NotificationLivePushBackend implements LivePushBackend {
  NotificationLivePushBackend(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<bool> isAvailable() async {
    if (_ready) return true;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      _ready = await _plugin.initialize(
            const InitializationSettings(android: androidInit, iOS: iosInit),
          ) ??
          false;
      return _ready;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(String tripId, LivePushContent initial) => _show(tripId, initial);

  @override
  Future<void> update(String tripId, LivePushContent content) => _show(tripId, content);

  @override
  Future<void> stop(String tripId) async {
    await _plugin.cancel(tripId.hashCode);
  }

  Future<void> _show(String tripId, LivePushContent c) async {
    final body = [
      if (c.nextStation != null) '下一站 ${c.nextStation}',
      if (c.etaText != null) c.etaText!,
      if (c.transferCountdownText != null) c.transferCountdownText!,
    ].join(' · ');
    await _plugin.show(
      tripId.hashCode,
      '${c.trainNum} · ${c.stateLabel}',
      body.isEmpty ? '行程进行中' : body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'railgo_live_push',
          '行程实时活动',
          importance: Importance.low,
          ongoing: true,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// 聚合服务：优先原生通道（iOS ActivityKit / Android 前台服务 / 鸿蒙实况窗），失败降级通知。
class LivePushService {
  LivePushService({required this.backends, required this.fallback});

  final List<LivePushBackend> backends;
  final NotificationLivePushBackend fallback;
  LivePushBackend? _active;

  Future<void> start(String tripId, LivePushContent initial) async {
    for (final b in backends) {
      if (await b.isAvailable()) {
        await b.start(tripId, initial);
        _active = b;
        return;
      }
    }
    if (await fallback.isAvailable()) {
      await fallback.start(tripId, initial);
      _active = fallback;
    }
  }

  Future<void> update(String tripId, LivePushContent content) async {
    final active = _active;
    if (active == null) return;
    try {
      await active.update(tripId, content);
    } catch (_) {
      // 原生通道失效 → 降级通知
      _active = fallback;
      if (await fallback.isAvailable()) await fallback.start(tripId, content);
    }
  }

  Future<void> stop(String tripId) async {
    await _active?.stop(tripId);
    _active = null;
  }
}
