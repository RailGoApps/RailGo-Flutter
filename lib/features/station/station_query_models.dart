// lib/features/station/station_query_models.dart
//
// 车站查询 / 站到站查询 响应模型（纯解析，可单测）。
// 契约依据：api.railgo.dev 文档 366547236e0（/api/station/query）与
// 366464961e0（/api/train/sts_query，顶层数组）。
library;

class StationDetail {
  const StationDetail({
    required this.name,
    required this.telecode,
    required this.bureau,
    required this.city,
    required this.level,
    required this.pinyinTriple,
    required this.types,
    required this.passingTrains,
  });

  factory StationDetail.fromResponse(Map<String, dynamic> resp) {
    final d = (resp['data'] as Map?) ?? const {};
    final trains = (resp['trains'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(PassingTrain.fromMap)
        .toList(growable: false);
    return StationDetail(
      name: _s(d['name']),
      telecode: _s(d['telecode']),
      bureau: _s(d['bureau']),
      city: _s(d['city']),
      level: _s(d['level']),
      pinyinTriple: _s(d['pinyinTriple']),
      types: ((d['type'] as List?) ?? const []).map(_s).toList(),
      passingTrains: trains,
    );
  }

  final String name;
  final String telecode;
  final String bureau;
  final String city;
  final String level;
  final String pinyinTriple;
  final List<String> types;
  final List<PassingTrain> passingTrains;
}

class PassingTrain {
  const PassingTrain({
    required this.number,
    required this.arrive,
    required this.depart,
    required this.fromStation,
    required this.toStation,
    required this.stopMinutes,
    required this.type,
  });

  factory PassingTrain.fromMap(Map<dynamic, dynamic> m) => PassingTrain(
        number: _s(m['number']),
        arrive: _s(m['arrive']),
        depart: _s(m['depart']),
        fromStation: _s((m['fromStation'] as Map?)?['station']),
        toStation: _s((m['toStation'] as Map?)?['station']),
        stopMinutes: (m['stopTime'] as num?)?.toInt() ?? 0,
        type: _s(m['type']),
      );

  final String number;
  final String arrive;
  final String depart;
  final String fromStation;
  final String toStation;
  final int stopMinutes;
  final String type;
}

class StsRoute {
  const StsRoute({
    required this.number,
    required this.type,
    required this.car,
    required this.fromDepart,
    required this.toArrive,
    required this.passTime,
    required this.dayDiff,
  });

  /// sts_query 顶层数组元素（文档 366464961e0）
  factory StsRoute.fromMap(Map<dynamic, dynamic> m) => StsRoute(
        number: _s(m['number']),
        type: _s(m['type']),
        car: _s(m['car']),
        fromDepart: _s(m['fromDepart']),
        toArrive: _s(m['toArrive']),
        passTime: _s(m['passTime']),
        dayDiff: (m['dayDiff'] as num?)?.toInt() ?? 0,
      );

  final String number;
  final String type;
  final String car;
  final String fromDepart;
  final String toArrive;
  final String passTime;
  final int dayDiff;
}

List<StsRoute> parseStsRoutes(List<dynamic> raw) =>
    raw
        .whereType<Map<dynamic, dynamic>>()
        .map(StsRoute.fromMap)
        .toList(growable: false);

String _s(Object? v) => v?.toString() ?? '';
