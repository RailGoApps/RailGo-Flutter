// lib/features/trip/trip_state_machine.dart
//
// 行程状态机（纯离线模式，Phase 2 §4.1）：
//   完全依赖本地缓存时刻表与系统时间比对；不请求网络、不依赖定位。
//   定时器由上层按 nextChangeAt 安排（避免轮询死循环——红队审查点）。
//
// 状态流转：
//   idle(未开始) → departingSoon(即将出发, 发车前2h内) → nextStation(下一站, 距到站>15min)
//   → arrivingSoon(即将到达, ≤15min) → stopped(正在停靠) → [循环] → finished(行程结束)
library;

import '../../core/utils/railgo_time.dart';

/// 单站时刻（day 为相对发车日偏移；arrive/depart 为 "HH:mm"，可缺省）
class TripStop {
  const TripStop({
    required this.station,
    required this.telecode,
    this.arrive,
    this.depart,
    this.day = 0,
  });

  final String station;
  final String telecode;
  final String? arrive;
  final String? depart;
  final int day;
}

class TripTimetable {
  const TripTimetable({required this.trainNum, required this.stops});

  final String trainNum;
  final List<TripStop> stops;

  bool get isValid => stops.length >= 2;
}

enum TripPhase {
  /// 未到发车前 2 小时
  idle,

  /// 即将出发：now ≥ 计划发车时间 - 2h
  departingSoon,

  /// 下一站***：运行中，距下一站到站 > 15 分钟
  nextStation,

  /// 即将到达：距下一站到站 ≤ 15 分钟
  arrivingSoon,

  /// 正在停靠：now ≥ 计划到站时间 且 ≤ 计划发车时间
  stopped,

  /// 行程结束（终到站到达）
  finished,
}

class TripStatus {
  const TripStatus({
    required this.phase,
    this.currentStopIndex,
    this.nextStopIndex,
    this.nextChangeAtMinutes,
    this.reason,
  });

  final TripPhase phase;
  final int? currentStopIndex;
  final int? nextStopIndex;
  /// 状态将在该绝对分钟数（相对发车日零点）发生变化；null = 不再变化（finished/idle 无起点）
  final int? nextChangeAtMinutes;
  final String? reason;
}

/// 阈值常量（与任务书 §4.1 绑定）
const Duration kDepartureWindow = Duration(hours: 2);
const Duration kArrivingWindow = Duration(minutes: 15);

class TripStateMachine {
  /// 评估当前状态。nowMinutes：相对发车日 00:00 的绝对分钟数（含跨日）。
  TripStatus evaluate({
    required TripTimetable timetable,
    required int nowMinutes,
  }) {
    if (!timetable.isValid) {
      return const TripStatus(phase: TripPhase.finished, reason: 'invalid_timetable');
    }
    final first = _absDepart(timetable.stops.first);
    if (first == null) {
      return const TripStatus(phase: TripPhase.finished, reason: 'missing_first_depart');
    }
    // 终到：以最后一站到达（或出发）为终点
    final last = timetable.stops.last;
    final lastMark = _absArrive(last) ?? _absDepart(last);
    if (lastMark != null && nowMinutes > lastMark) {
      return TripStatus(phase: TripPhase.finished, currentStopIndex: timetable.stops.length - 1);
    }

    // 发车前窗口
    if (nowMinutes < first - kDepartureWindow.inMinutes) {
      return TripStatus(
        phase: TripPhase.idle,
        nextChangeAtMinutes: first - kDepartureWindow.inMinutes,
      );
    }
    if (nowMinutes < first) {
      return TripStatus(phase: TripPhase.departingSoon, nextChangeAtMinutes: first);
    }

    // 逐站扫描
    for (var i = 1; i < timetable.stops.length; i++) {
      final stop = timetable.stops[i];
      final arrive = _absArrive(stop);
      final depart = _absDepart(stop);

      if (arrive != null && nowMinutes < arrive) {
        // 运行区间：距下一站到站
        final remain = arrive - nowMinutes;
        if (remain > kArrivingWindow.inMinutes) {
          return TripStatus(
            phase: TripPhase.nextStation,
            currentStopIndex: i - 1,
            nextStopIndex: i,
            nextChangeAtMinutes: arrive - kArrivingWindow.inMinutes,
          );
        }
        return TripStatus(
          phase: TripPhase.arrivingSoon,
          currentStopIndex: i - 1,
          nextStopIndex: i,
          nextChangeAtMinutes: arrive,
        );
      }
      if (arrive != null && nowMinutes >= arrive) {
        final stopEnd = depart ?? arrive; // 终到站无 depart，停靠即结束
        if (nowMinutes <= stopEnd) {
          final isTerminal = i == timetable.stops.length - 1;
          return TripStatus(
            phase: isTerminal ? TripPhase.finished : TripPhase.stopped,
            currentStopIndex: i,
            nextStopIndex: isTerminal ? null : (i + 1 < timetable.stops.length ? i + 1 : null),
            nextChangeAtMinutes: isTerminal ? null : stopEnd,
          );
        }
        // 已过本站出发时间 → 进入下一区间（继续循环）
        if (i == timetable.stops.length - 1) {
          return TripStatus(phase: TripPhase.finished, currentStopIndex: i);
        }
      }
      // 到达缺失（数据异常）：以出发时间为界推进，防死循环
      if (arrive == null && depart != null && nowMinutes < depart) {
        return TripStatus(
          phase: TripPhase.nextStation,
          currentStopIndex: i - 1,
          nextStopIndex: i,
          nextChangeAtMinutes: depart - kArrivingWindow.inMinutes,
          reason: 'missing_arrive_fallback',
        );
      }
      if (arrive == null && depart == null) {
        continue; // 全空站跳过（不阻塞推进）
      }
    }
    return TripStatus(
      phase: TripPhase.finished,
      currentStopIndex: timetable.stops.length - 1,
      reason: 'loop_exit',
    );
  }

  static int? _absArrive(TripStop s) {
    final m = parseTimeToMinutes(s.arrive);
    return m == null ? null : s.day * 1440 + m;
  }

  static int? _absDepart(TripStop s) {
    final m = parseTimeToMinutes(s.depart);
    return m == null ? null : s.day * 1440 + m;
  }
}
