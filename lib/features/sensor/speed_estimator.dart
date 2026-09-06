// lib/features/sensor/speed_estimator.dart
//
// 传感器辅助测速（任务书 §4.5 兜底模式，原项目无此功能——Baseline §0/#5）：
//   触发条件：系统定位不可用 + 速度无法获取（GMS/HMS 均不可用），自动切换，无需手动开启。
//   算法：合加速度 a = √(ax²+ay²+az²) − g → 梯形法数值积分 v = ∫a dt → 速度误差带。
//   ⚠️ 状态机不消费本模块输出（仅辅助显示）；定位恢复时调用 [reset] 重新锚定。
library;

import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

class SpeedSample {
  const SpeedSample({
    required this.timestamp,
    required this.speedMs,
    required this.minusErrorMs,
    required this.plusErrorMs,
    required this.satelliteWeak,
  });

  final DateTime timestamp;

  /// 估算速度 m/s（仅前向运动假设，长时间会漂移——故必须显示误差带）
  final double speedMs;
  final double minusErrorMs;
  final double plusErrorMs;
  final bool satelliteWeak;
}

class AccelerometerSpeedEstimator {
  AccelerometerSpeedEstimator({
    this.gravity = 9.80665,
    this.sensorNoiseSigma = 0.1, // m/s²，任务书示例 ±0.1
    this.maxSamples = 512,
    this.decayHalfLife = const Duration(seconds: 45),
  });

  final double gravity;
  final double sensorNoiseSigma;
  final int maxSamples;
  final Duration decayHalfLife;

  double _integral = 0; // m/s
  DateTime? _lastTs;
  final List<({DateTime t, double a})> _history = [];

  /// 传感器精度（部分设备可通过 platform channel 获取，默认 ±0.1）
  double sensorAccuracy = 0.1;

  /// 是否已锚定（首样本只建立时间基准，不积分）
  bool get isAnchored => _lastTs != null;

  double get speedMetersPerSecond => _integral < 0 ? 0 : _integral;

  /// 喂入加速度样本（sensors_plus 的 Triple/AccelerometerEvent；now 可注入便于测试）
  SpeedSample feed(Triple triple, {DateTime? now}) => feedValues(triple.x, triple.y, triple.z, now: now);

  /// 与 Triple 构造器解耦的数值入口（测试/无传感器环境使用）
  SpeedSample feedValues(double x, double y, double z, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    final a = _resultantAcceleration(x, y, z);
    if (_lastTs == null) {
      _lastTs = ts;
      _history.add((t: ts, a: a));
      return _sample(ts);
    }
    final dt = ts.difference(_lastTs!).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 5) {
      // 时钟回跳/异常间隔：丢弃并重新锚定（红队：极端输入防御）
      _lastTs = ts;
      return _sample(ts);
    }
    // 梯形积分
    final lastA = _history.isEmpty ? a : _history.last.a;
    _integral += 0.5 * (lastA + a) * dt;
    _lastTs = ts;
    _history.add((t: ts, a: a));
    if (_history.length > maxSamples) _history.removeAt(0);
    return _sample(ts);
  }

  SpeedSample _sample(DateTime ts) {
    final elapsed = _history.isEmpty ? 0 : ts.difference(_history.first.t).inMicroseconds / 1e6;
    // 误差传播：传感器噪声经积分放大 σ_v ≈ σ_a · t/√2 + 精度限
    final sigma = math.sqrt(elapsed / 2) * sensorNoiseSigma + sensorAccuracy * elapsed * 0.5;
    final speed = speedMetersPerSecond;
    return SpeedSample(
      timestamp: ts,
      speedMs: speed,
      minusErrorMs: math.min(sigma, speed), // 下界不为负
      plusErrorMs: sigma,
      satelliteWeak: true,
    );
  }

  /// 定位恢复 → 清零重新锚定（任务书 §4.5：自动切回系统定位并重置积分）
  void reset() {
    _integral = 0;
    _lastTs = null;
    _history.clear();
  }

  /// 合加速度去重力（模长法；静止/匀速时 ≈ 0）
  double _resultantAcceleration(double x, double y, double z) {
    final mag = math.sqrt(x * x + y * y + z * z);
    return mag - gravity;
  }

  /// 是否应启用兜底模式（定位不可用判定由上层 LocationService 给出）
  static bool shouldFallback({required bool locationAvailable, required bool hasSpeed}) =>
      !locationAvailable || !hasSpeed;
}

/// 显示格式化："当前速度：85 ± 3 km/h"（任务书 §4.5）
String formatSpeedWithBand(SpeedSample s) {
  final v = (s.speedMs * 3.6).round();
  final band = ((s.plusErrorMs) * 3.6).round();
  return '当前速度：$v ± $band km/h';
}
