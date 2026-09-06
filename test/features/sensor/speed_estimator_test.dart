// test/features/sensor/speed_estimator_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/sensor/speed_estimator.dart';

// 直接使用 feedValues(x,y,z)，避免依赖 sensors_plus 的 Triple 构造器形态

void main() {
  group('加速度积分测速', () {
    test('静止输入（仅重力）→ 速度恒 0', () {
      final e = AccelerometerSpeedEstimator();
      var now = DateTime(2025, 1, 1, 8);
      var s = e.feedValues(0, 0, 9.80665, now: now); // 锚定
      for (var i = 1; i <= 50; i++) {
        now = now.add(const Duration(milliseconds: 20));
        s = e.feedValues(0, 0, 9.80665, now: now);
      }
      expect(s.speedMs, closeTo(0, 1e-6));
      expect(e.speedMetersPerSecond, 0);
    });

    test('恒定 0.1 m/s² 加速 10s → v ≈ 1 m/s，误差带随时间放大', () {
      final e = AccelerometerSpeedEstimator();
      var now = DateTime(2025, 1, 1, 8);
      // 合加速度 0.1 → 例如 (0.1, 0, g) 的模长 ≈ g + 0.1（近似）
      final ax = math.sqrt(math.pow(9.80665 + 0.1, 2) - math.pow(9.80665, 2));
      e.feedValues(ax, 0, 9.80665, now: now);
      SpeedSample last = e.feedValues(ax, 0, 9.80665, now: now);
      for (var i = 1; i <= 500; i++) {
        now = now.add(const Duration(milliseconds: 20));
        last = e.feedValues(ax, 0, 9.80665, now: now);
      }
      // 10s × 0.1 m/s² = 1 m/s（数值梯形近似）
      expect(last.speedMs, closeTo(1.0, 0.05));
      expect(last.plusErrorMs, greaterThan(0));
      expect(last.satelliteWeak, isTrue);
    });

    test('显示格式："当前速度：X ± Y km/h"', () {
      final s = SpeedSample(
        timestamp: DateTime.now(),
        speedMs: 85 / 3.6,
        minusErrorMs: 0.5,
        plusErrorMs: 0.833,
        satelliteWeak: true,
      );
      final text = formatSpeedWithBand(s);
      expect(text, startsWith('当前速度：85 ± '));
      expect(text, endsWith('km/h'));
    });

    test('时间回跳/异常间隔：丢弃样本不崩溃不产生负速度', () {
      final e = AccelerometerSpeedEstimator();
      final t0 = DateTime(2025, 1, 1, 8);
      e.feedValues(0, 0, 9.80665, now: t0);
      // 回跳
      final s1 = e.feedValues(0, 0, 9.80665, now: t0.subtract(const Duration(seconds: 3)));
      expect(s1.speedMs, 0);
      // 超长间隔
      final s2 = e.feedValues(0, 0, 9.80665, now: t0.add(const Duration(seconds: 30)));
      expect(s2.speedMs, 0);
    });

    test('reset 后重新锚定（定位恢复场景）', () {
      final e = AccelerometerSpeedEstimator();
      var now = DateTime(2025, 1, 1, 8);
      e.feedValues(0.5, 0, 9.80665, now: now);
      for (var i = 1; i <= 100; i++) {
        now = now.add(const Duration(milliseconds: 20));
        e.feedValues(0.5, 0, 9.80665, now: now);
      }
      expect(e.speedMetersPerSecond, greaterThan(0));
      e.reset();
      expect(e.isAnchored, isFalse);
      expect(e.speedMetersPerSecond, 0);
    });

    test('兜底触发条件', () {
      expect(AccelerometerSpeedEstimator.shouldFallback(locationAvailable: false, hasSpeed: false), isTrue);
      expect(AccelerometerSpeedEstimator.shouldFallback(locationAvailable: true, hasSpeed: false), isTrue);
      expect(AccelerometerSpeedEstimator.shouldFallback(locationAvailable: true, hasSpeed: true), isFalse);
    });
  });
}
