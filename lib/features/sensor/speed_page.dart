// lib/features/sensor/speed_page.dart
//
// 实时测速页（基线 pages/speed/speed.vue 移植 + 任务书 §4.5 传感器兜底增强）：
//   定位可用 → 系统 GPS 速度（geolocator，500ms 轮询，高/低精度切换）
//   定位不可用 → 加速度计积分估算 + "卫星信号弱/传感器辅助模式"标识 + 误差带
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'speed_estimator.dart';

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key});
  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  final _estimator = AccelerometerSpeedEstimator();
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _gpsTimer;
  Position? _lastPosition;
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
    // 权限请求失败 → 自动落入传感器辅助模式（shouldFallback）
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
    _gpsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy:
                _highAccuracy ? LocationAccuracy.best : LocationAccuracy.low,
          ),
        );
        if (mounted) setState(() => _lastPosition = pos);
      } catch (_) {
        // 单次失败忽略（兜底模式判定依赖连续失败）
      }
    });
  }

  bool get _gpsSpeedAvailable =>
      _lastPosition != null &&
      (_lastPosition!.speed > 0 || _lastPosition!.accuracy < 100);

  @override
  void dispose() {
    _accelSub?.cancel();
    _gpsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assistActive = AccelerometerSpeedEstimator.shouldFallback(
          locationAvailable: _lastPosition != null,
          hasSpeed: _gpsSpeedAvailable,
        ) &&
        _assistSample != null;
    final kmh = _gpsSpeedAvailable
        ? (_lastPosition!.speed * 3.6).round()
        : (_assistSample != null ? (_assistSample!.speedMs * 3.6).round() : 0);
    return Scaffold(
      appBar: AppBar(title: const Text('实时测速')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      if (assistActive)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Chip(
                            avatar:
                                Icon(Icons.satellite_alt_outlined, size: 16),
                            label:
                                Text('卫星信号弱', style: TextStyle(fontSize: 11)),
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
                  Text(_lastPosition != null ? '您的速度' : '传感器辅助估算',
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ),
          if (assistActive && _assistSample != null) ...[
            Text(formatSpeedWithBand(_assistSample!),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text('传感器辅助模式：加速度积分估算，仅供参考',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black45)),
          ] else
            const Text('定位服务由系统提供，测速信息仅供参考',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('高精度定位'),
            value: _highAccuracy,
            onChanged: (v) => setState(() => _highAccuracy = v),
          ),
          if (_lastPosition != null) ...[
            _kv('经度', _lastPosition!.longitude.toStringAsFixed(5)),
            _kv('纬度', _lastPosition!.latitude.toStringAsFixed(5)),
            _kv('海拔', '${_lastPosition!.altitude.toStringAsFixed(0)}m'),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.black54)),
            Text(v)
          ],
        ),
      );
}
