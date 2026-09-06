// test/core/utils/coord_transform_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/utils/coord_transform.dart';

void main() {
  group('GCJ-02 ↔ WGS-84', () {
    test('中国境内互逆一致（误差 < 2e-5 度）', () {
      const wgsLat = 39.90734, wgsLng = 116.39734; // 北京附近
      final (gcjLat, gcjLng) = wgs84ToGcj02(wgsLat, wgsLng);
      expect(gcjLat, isNot(closeTo(wgsLat, 1e-6))); // 确有偏移
      final (backLat, backLng) = gcj02ToWgs84(gcjLat, gcjLng);
      expect(backLat, closeTo(wgsLat, 2e-5));
      expect(backLng, closeTo(wgsLng, 2e-5));
    });

    test('境外坐标原样返回', () {
      final (lat, lng) = gcj02ToWgs84(35.6762, 139.6503); // 东京
      expect(lat, 35.6762);
      expect(lng, 139.6503);
      final (lat2, lng2) = wgs84ToGcj02(35.6762, 139.6503);
      expect(lat2, 35.6762);
      expect(lng2, 139.6503);
    });

    test('经典偏移量级（北京约数百米）', () {
      const wgsLat = 39.90734, wgsLng = 116.39734;
      final (gcjLat, gcjLng) = wgs84ToGcj02(wgsLat, wgsLng);
      final dLatM = (gcjLat - wgsLat) * 111320;
      final dLngM = (gcjLng - wgsLng) * 111320 * 0.77; // cos(39.9°)
      expect(dLatM.abs(), lessThan(1000));
      expect(dLngM.abs(), lessThan(1000));
      expect(dLatM.abs() + dLngM.abs(), greaterThan(100));
    });
  });

  group('MapLineData 解析（基线 mapLine 结构）', () {
    test('stations/train 段解析 + GCJ→WGS 自动转换 + 按 index 排序', () {
      final data = MapLineData.parseGCJ({
        'stations': [
          {'北京南': [116.37863, 39.86532]},
          {'上海虹桥': [121.31589, 31.19363]},
        ],
        'train': {
          'b': {'index': 2, 'line': [[117.0, 36.5], [118.0, 36.6]]},
          'a': {'index': 1, 'line': [[116.4, 39.8], [117.0, 36.5]]},
        },
      });
      expect(data.stations.length, 2);
      expect(data.stations.first.name, '北京南');
      expect(data.segments.first.index, 1);
      expect(data.segments.length, 2);
      // WGS 与 GCJ 不相等（已转换）
      expect(data.stations.first.lng, isNot(116.37863));
    });

    test('脏数据容错：空/缺字段不抛异常', () {
      final data = MapLineData.parseGCJ({});
      expect(data.stations, isEmpty);
      expect(data.segments, isEmpty);
      final data2 = MapLineData.parseGCJ({'stations': ['junk', <String, dynamic>{}], 'train': 'bad'});
      expect(data2.stations, isEmpty);
    });
  });

  group('投影归一化', () {
    test('中心点投影到 (0.5, 0.5)，边界在 0..1 内', () {
      final (nx, ny) = projectNormalized(116.5, 37.0, 116.0, 117.0, 36.5, 37.5);
      expect(nx, 0.5);
      expect(ny, 0.5);
      final (nx2, ny2) = projectNormalized(116.0, 37.5, 116.0, 117.0, 36.5, 37.5);
      expect(nx2, closeTo(0.0, 0.26)); // 等比保形下 lng 半径只占一半
      expect(ny2, closeTo(0.0, 0.05));
      expect(nx2, greaterThanOrEqualTo(0));
      expect(ny2, greaterThanOrEqualTo(0));
    });

    test('空数据 bounds 返回单位盒', () {
      final b = mapLineBounds(const MapLineData(stations: [], segments: []));
      expect(b.minLng, 0);
      expect(b.maxLng, 1);
    });
  });
}
