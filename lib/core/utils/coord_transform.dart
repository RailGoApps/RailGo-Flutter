// lib/core/utils/coord_transform.dart
//
// 坐标转换（基线 scripts/coord_transform.js 移植）：
//   GCJ-02（国测局/火星坐标，V2 mapLine 返回）→ WGS-84（GPS/国际标准）
//   供线路点地图组件与未来 flutter_map 瓦片层使用。
library;

import 'dart:math' as math;

const double _kA = 6378245.0;
const double _kEe = 0.00669342162296594323;

bool outOfChina(double lng, double lat) =>
    lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;

double _transformLat(double x, double y) {
  var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
  return ret;
}

(double dLat, double dLng) _delta(double lng, double lat) {
  var dLat = _transformLat(lng - 105.0, lat - 35.0);
  var dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - _kEe * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) / ((_kA * (1 - _kEe)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (_kA / sqrtMagic * math.cos(radLat) * math.pi);
  return (dLat, dLng);
}

/// WGS-84 → GCJ-02
(double gcjLat, double gcjLng) wgs84ToGcj02(double wgsLat, double wgsLng) {
  if (outOfChina(wgsLng, wgsLat)) return (wgsLat, wgsLng);
  final (dLat, dLng) = _delta(wgsLng, wgsLat);
  return (wgsLat + dLat, wgsLng + dLng);
}

/// GCJ-02 → WGS-84（一次反向迭代精化，误差 < 1e-6 度量级）
(double wgsLat, double wgsLng) gcj02ToWgs84(double gcjLat, double gcjLng) {
  if (outOfChina(gcjLng, gcjLat)) return (gcjLat, gcjLng);
  final (dLat, dLng) = _delta(gcjLng, gcjLat);
  var wgsLat = gcjLat - dLat;
  var wgsLng = gcjLng - dLng;
  // 精化一轮
  final (dLat2, dLng2) = _delta(wgsLng, wgsLat);
  wgsLat = gcjLat - dLat2;
  wgsLng = gcjLng - dLng2;
  return (wgsLat, wgsLng);
}

/// 地图线路数据模型（V2 /api/v2/mapLine 返回结构，基线 trainResult.vue 实证）：
///   stations: [{站名: [lng, lat]}]（GCJ-02）
///   train:    {segKey: {index, line: [[lng,lat], ...]}}
class MapLineData {
  const MapLineData({required this.stations, required this.segments});

  factory MapLineData.fromWgs({
    required List<({String name, double lng, double lat})> stations,
    required List<({int index, List<({double lng, double lat})> line})> segments,
  }) =>
      MapLineData(stations: stations, segments: segments);

  /// 解析 mapLine 原始 JSON（自动 GCJ-02 → WGS-84）
  factory MapLineData.parseGCJ(Map<String, dynamic> raw) {
    final stations = <({String name, double lng, double lat})>[];
    for (final s in (raw['stations'] as List<dynamic>? ?? <dynamic>[])) {
      if (s is Map && s.isNotEmpty) {
        final name = s.keys.first;
        final c = s.values.first;
        if (c is List && c.length >= 2) {
          final (wLat, wLng) = gcj02ToWgs84(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
          );
          stations.add((name: name, lng: wLng, lat: wLat));
        }
      }
    }
    final segments = <({int index, List<({double lng, double lat})> line})>[];
    final train = raw['train'];
    if (train is Map) {
      for (final seg in train.values) {
        if (seg is Map && seg['line'] is List) {
          final pts = <({double lng, double lat})>[];
          for (final p in (seg['line'] as List)) {
            if (p is List && p.length >= 2) {
              final (wLat, wLng) = gcj02ToWgs84((p[1] as num).toDouble(), (p[0] as num).toDouble());
              pts.add((lng: wLng, lat: wLat));
            }
          }
          segments.add((index: (seg['index'] as num? ?? 0).toInt(), line: pts));
        }
      }
      segments.sort((a, b) => a.index.compareTo(b.index));
    }
    return MapLineData(stations: stations, segments: segments);
  }

  final List<({String name, double lng, double lat})> stations;
  final List<({int index, List<({double lng, double lat})> line})> segments;
}

/// 归一化包围盒（纯函数，供画布投影与单测）
({double minLng, double maxLng, double minLat, double maxLat}) mapLineBounds(MapLineData d) {
  var minLng = double.infinity, maxLng = double.negativeInfinity;
  var minLat = double.infinity, maxLat = double.negativeInfinity;
  void include(double lng, double lat) {
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
  }

  for (final s in d.stations) {
    include(s.lng, s.lat);
  }
  for (final seg in d.segments) {
    for (final p in seg.line) {
      include(p.lng, p.lat);
    }
  }
  if (minLng == double.infinity) return (minLng: 0, maxLng: 1, minLat: 0, maxLat: 1);
  return (minLng: minLng, maxLng: maxLng, minLat: minLat, maxLat: maxLat);
}

/// 经纬度 → 0..1 归一化画布坐标（等比保形：以最大跨度缩放）
(double nx, double ny) projectNormalized(
  double lng,
  double lat,
  double minLng,
  double maxLng,
  double minLat,
  double maxLat,
) {
  final spanLng = (maxLng - minLng).abs().clamp(1e-9, double.infinity);
  final spanLat = (maxLat - minLat).abs().clamp(1e-9, double.infinity);
  final span = math.max(spanLng, spanLat);
  final cx = (minLng + maxLng) / 2;
  final cy = (minLat + maxLat) / 2;
  return (((lng - cx) / span) + 0.5, 0.5 - ((lat - cy) / span));
}
