// lib/core/utils/clock.dart
//
// 可注入时钟 + 防篡改守卫。
// 行程状态机完全依赖系统时间比对（纯离线），但本地时间可能被用户手动改动，
// 因此 TrustworthyClock 同时维护【墙钟锚点】与【单调秒表】：
//   - 正常情况：以单调流逝推算当前时刻（不受中途改时间影响）
//   - 检测到墙钟与推算值偏差超过阈值（默认 90s）：判定时间被篡改/大幅校准，
//     重新锚定并上报事件（UI 可提示"检测到系统时间变化，行程进度已重新校准"）
library;

import 'dart:async';

abstract class AppClock {
  DateTime now();
}

class SystemClock implements AppClock {
  @override
  DateTime now() => DateTime.now();
}

enum ClockEvent { reanchored }

class TrustworthyClock implements AppClock {
  TrustworthyClock({AppClock? wallClock, this.driftTolerance = const Duration(seconds: 90), DateTime? initial})
      : _wall = wallClock ?? SystemClock() {
    _anchorWall = initial ?? _wall.now();
    _mono = Stopwatch()..start();
  }

  final AppClock _wall;
  final Duration driftTolerance;
  late DateTime _anchorWall;
  late Stopwatch _mono;

  /// 检测到时间跳变时广播（UI 提示 / 日志）
  final StreamController<ClockEvent> _events = StreamController<ClockEvent>.broadcast();
  Stream<ClockEvent> get events => _events.stream;

  /// 是否发生过重新锚定（红队审查点：状态机不得因时间篡改死循环）
  bool get hasReanchored => _reanchorCount > 0;
  int _reanchorCount = 0;

  @override
  DateTime now() {
    final projected = _anchorWall.add(_mono.elapsed);
    final wall = _wall.now();
    final drift = wall.difference(projected).abs();
    if (drift > driftTolerance) {
      // 墙钟被大幅修改（或 NTP 校准）：以墙钟为新锚点重新出发
      _anchorWall = wall;
      _mono.reset();
      _reanchorCount++;
      _events.add(ClockEvent.reanchored);
      return wall;
    }
    return projected;
  }
}
