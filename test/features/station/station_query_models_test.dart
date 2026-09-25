// 车站查询 / 站到站 响应模型解析（契约：api.railgo.dev 366547236e0 / 366464961e0）
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/station/station_query_models.dart';

void main() {
  test('StationDetail.fromResponse：车站信息 + 途经车次（实测响应形状）', () {
    final d = StationDetail.fromResponse({
      'data': {
        'telecode': 'XBG',
        'name': '新余北',
        'bureau': '南昌局',
        'city': '新余市',
        'level': '未知',
        'pinyinTriple': 'XYB',
        'type': ['客', '高'],
      },
      'trains': [
        {
          'number': 'G485',
          'arrive': '15:48',
          'depart': '15:51',
          'stopTime': 3,
          'type': '高速',
          'fromStation': {'station': '北京', 'stationTelecode': 'BJP'},
          'toStation': {'station': '南昌西', 'stationTelecode': 'NXG'},
        },
        'junk-row',
      ],
    });
    expect(d.name, '新余北');
    expect(d.telecode, 'XBG');
    expect(d.bureau, '南昌局');
    expect(d.types, ['客', '高']);
    expect(d.passingTrains, hasLength(1));
    final t = d.passingTrains.first;
    expect(t.number, 'G485');
    expect(t.fromStation, '北京');
    expect(t.toStation, '南昌西');
    expect(t.stopMinutes, 3);
  });

  test('StationDetail 空响应/缺字段容错', () {
    final d = StationDetail.fromResponse({});
    expect(d.name, '');
    expect(d.passingTrains, isEmpty);
  });

  test('parseStsRoutes：顶层数组（sts_query 契约）', () {
    final routes = parseStsRoutes([
      {
        'number': 'G3',
        'type': '高速',
        'car': 'CR400BF-B',
        'fromDepart': '07:40',
        'toArrive': '12:32',
        'passTime': '4时52分',
        'dayDiff': 0,
      },
      {
        'number': 'D5',
        'type': '动车',
        'car': 'CR200J',
        'fromDepart': '21:21',
        'toArrive': '09:27',
        'passTime': '12时6分',
        'dayDiff': 1,
      },
      'not-a-map',
    ]);
    expect(routes, hasLength(2));
    expect(routes.first.number, 'G3');
    expect(routes.first.passTime, '4时52分');
    expect(routes.last.dayDiff, 1);
  });
}
