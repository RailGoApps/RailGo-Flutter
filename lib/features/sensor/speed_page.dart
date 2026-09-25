// lib/features/sensor/speed_page.dart
//
// 实时测速视图（可嵌入行程 Tab——用户 UX 要求合并；原独立页面已移除）。
//
// 定位来源三态（用户反馈修复）：
//   GPS 卫星（accuracy ≤ 25m）｜基站/WiFi（新鲜但低精度）｜加速度计兜底。
// 切换修复：
//   1) 位置新鲜度 10s 窗口——信号丢失后速度不再"冻结"在旧值；
//   2) 加速度计兜底 → 定位恢复 的瞬间 reset() 积分器，
//      消除兜底期间漂移累积导致的错误速度（旧实现从未 reset 的核心 bug）；
//   3) 每秒重估来源，GPS 轮询在途互斥防堆叠。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/l10n/app_localizations.dart';
import 'speed_estimator.dart';

class SpeedMonitorView extends StatefulWidget {
  const SpeedMonitorView({super.key});

  @override
  State<SpeedMonitorView> createState() => _SpeedMonitorViewState();
}

class _SpeedMonitorViewState extends State<SpeedMonitorView> {
  final _estimator = AccelerometerSpeedEstimator();
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _gpsTimer;
  bool _polling = false; // 单次定位未返回时不发起新一拍
  Position? _lastPosition;
  SpeedSource _source = SpeedSource.accelerometer;
  bool _highAccuracy = false;
  SpeedSample? _assistSample;

  @override
  void initState() {
    super.initState();
    _startAccelerometer();
    _startGpsPolling();
  }

  void _startAccelerometer() {
    _accelSub = accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 20))
        .listen((event) {
      final sample = _estimator.feed(event);
      if (mounted) setState(() => _assistSample = sample);
    }, onError: (Object _) {
      // 传感器不可用 → 纯时间驱动降级（任务书：禁用测速 UI）
    });
  }

  Future<void> _startGpsPolling() async {
    // 权限请求失败 → 自动落入加速度计兜底
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    } catch (_) {
      return;
    }
    _gpsTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      _refreshSource(); // 每秒重估新鲜度（信号丢失即时切兜底）
      if (_polling) return;
      _polling = true;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy:
                _highAccuracy ? LocationAccuracy.best : LocationAccuracy.low,
          ),
        );
        if (mounted) _applyPosition(pos);
      } catch (_) {
        // 单次失败忽略（来源判定依赖新鲜度窗口）
      }
      _polling = false;
    });
  }

  void _applyPosition(Position pos) {
    final next = classifySpeedSource(
      positionTime: pos.timestamp,
      accuracy: pos.accuracy,
      now: DateTime.now(),
    );
    // 核心修复：兜底 → 定位恢复 的边沿触发积分器清零
    if (_source == SpeedSource.accelerometer &&
        next != SpeedSource.accelerometer) {
      _estimator.reset();
    }
    setState(() => _lastPosition = pos);
    _source = next;
  }

  void _refreshSource() {
    final pos = _lastPosition;
    final s = classifySpeedSource(
      positionTime: pos?.timestamp,
      accuracy: pos?.accuracy,
      now: DateTime.now(),
    );
    if (s == _source) return;
    if (mounted) {
      setState(() => _source = s);
    } else {
      _source = s;
    }
  }

  bool get _locationSpeedUsable =>
      _source == SpeedSource.gps || _source == SpeedSource.network;

  @override
  void dispose() {
    _accelSub?.cancel();
    _gpsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final subtle = cs.onSurfaceVariant;
    final pos = _lastPosition;
    final kmh = _locationSpeedUsable
        ? ((pos?.speed ?? 0) * 3.6).round()
        : (_assistSample != null ? (_assistSample!.speedMs * 3.6).round() : 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Stack(
                  alignment: AlignmentDirectional.topEnd,
                  children: [
                    if (_source != SpeedSource.gps)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Chip(
                          avatar: Icon(
                            _source == SpeedSource.network
                                ? Icons.cell_tower_outlined
                                : Icons.speed_outlined,
                            size: 16,
                          ),
                          label: Text(
                            switch (_source) {
                              SpeedSource.gps => l10n.speedSourceGps,
                              SpeedSource.network => l10n.speedSourceNetwork,
                              SpeedSource.accelerometer =>
                                l10n.speedSourceAccel,
                            },
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    Center(
                      child: Text('$kmh',
                          style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'DIN1451')),
                    ),
                  ],
                ),
                const Text('km/h'),
                const SizedBox(height: 8),
                Text(
                  _locationSpeedUsable
                      ? l10n.speedYourSpeed
                      : l10n.speedSensorEstimate,
                  style: TextStyle(color: subtle),
                ),
              ],
            ),
          ),
        ),
        if (_source == SpeedSource.accelerometer && _assistSample != null) ...[
          Text(formatSpeedWithBand(_assistSample!),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(l10n.speedAccelDisclaimer,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: subtle)),
        ] else
          Text(l10n.speedSystemProvider,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: subtle)),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(l10n.speedHighAccuracy),
          value: _highAccuracy,
          onChanged: (v) => setState(() => _highAccuracy = v),
        ),
        if (pos != null) ...[
          _kv(l10n.speedLon, pos.longitude.toStringAsFixed(5)),
          _kv(l10n.speedLat, pos.latitude.toStringAsFixed(5)),
          _kv(l10n.speedAlt, '${pos.altitude.toStringAsFixed(0)}m'),
          if (pos.accuracy.isFinite)
            _kv(l10n.speedAccuracy, '${pos.accuracy.toStringAsFixed(0)}m'),
        ],
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                k,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(v)
          ],
        ),
      );
}
