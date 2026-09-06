// lib/features/train/train_repository.dart
//
// 车次查询主链路（基线 §5.2 的 1:1 移植）：
//   在线：V2 getTrainMain 为主数据（失败/当日不开行 → 上层跳 404，不回退 V1）
//        → V1 /api/train/query 补交路+里程（失败仅告警不阻塞）
//        → 按 stationTelecode 合并 distance/speed
//   离线：SQLite 直查（OfflineDb）
library;

import '../../core/network/railgo_api.dart';
import '../../core/storage/offline_db.dart';
import '../trip/trip_state_machine.dart';

class TrainDetail {
  const TrainDetail({
    required this.trainNum,
    required this.bureau,
    required this.bureauShortName,
    required this.car,
    required this.carOwner,
    required this.runner,
    required this.numberFull,
    required this.numberKind,
    required this.rundays,
    required this.spend,
    required this.stops,
    this.diagram = const [],
    this.diagramType = '',
    this.v1ComplementFailed = false,
    this.fromOfflineDb = false,
  });

  final String trainNum;
  final String bureau;
  final String bureauShortName;
  final String car;
  final String carOwner;
  final String runner;
  final List<String> numberFull;
  final String numberKind;
  final List<String> rundays;
  final int spend;
  final List<TrainStopDetail> stops;
  final List<dynamic> diagram;
  final String diagramType;
  final bool v1ComplementFailed;
  final bool fromOfflineDb;
}

class TrainStopDetail {
  const TrainStopDetail({
    required this.station,
    required this.stationTelecode,
    required this.trainCode,
    required this.arrive,
    required this.depart,
    required this.day,
    this.distance = '-',
    this.speed = 0,
  });

  final String station;
  final String stationTelecode;
  final String trainCode;
  final String arrive;
  final String depart;
  final int day;
  final String distance;
  final int speed;
}

class TrainNotFoundException implements Exception {
  const TrainNotFoundException(this.trainNum);
  final String trainNum;
  @override
  String toString() => 'TrainNotFoundException: $trainNum 当日不开行或不存在';
}

class TrainRepository {
  TrainRepository(this._api, {this.offlineDb});

  final RailGoApi _api;
  final OfflineDb? offlineDb;

  /// 在线主链路（V2 主数据 + V1 补全合并）
  Future<TrainDetail> fetchOnline({required String trainNum, String? date}) async {
    final v2 = await _api.getTrainMain(trainNum: trainNum, date: date);
    final data = v2.data;
    if (data == null || data['success'] != true) {
      throw TrainNotFoundException(trainNum);
    }
    final d = data['data'] as Map<String, dynamic>?;
    final timetable = (d?['timetable'] as List<dynamic>? ?? <dynamic>[]);
    if (d == null || timetable.isEmpty) {
      throw TrainNotFoundException(trainNum);
    }

    // V1 补全（交路 + distance/speed）——失败静默
    Map<String, Map<String, dynamic>> v1Map = {};
    var v1Failed = false;
    List<dynamic> diagram = [];
    var diagramType = '';
    try {
      final v1 = await _api.trainQueryV1(trainNum);
      final v1Data = v1.data;
      if (v1Data != null && v1Data['error'] == null) {
        final v1Timetable = v1Data['timetable'] as List<dynamic>? ?? [];
        for (final item in v1Timetable) {
          if (item is Map && item['stationTelecode'] != null) {
            v1Map[item['stationTelecode'] as String] = Map<String, dynamic>.from(item);
          }
        }
        if (v1Data['diagram'] is List) {
          diagram = v1Data['diagram'] as List<dynamic>;
          diagramType = (v1Data['diagramType'] ?? '') as String;
        }
      }
    } on Exception {
      v1Failed = true; // 基线语义：V1 失败不影响主数据
    }

    final stops = <TrainStopDetail>[
      for (final raw in timetable)
        if (raw is Map)
          () {
            final s = Map<String, dynamic>.from(raw);
            return TrainStopDetail(
              station: (s['station'] ?? '').toString(),
              stationTelecode: (s['stationTelecode'] ?? '').toString(),
              trainCode: (s['trainCode'] ?? '').toString(),
              arrive: (s['arrive'] ?? '-').toString(),
              depart: (s['depart'] ?? '-').toString(),
              day: (s['day'] as num? ?? 0).toInt(),
              distance: (v1Map[s['stationTelecode']]?['distance'] ?? '-').toString(),
              speed: (v1Map[s['stationTelecode']]?['speed'] as num? ?? 0).toInt(),
            );
          }(),
    ];

    return TrainDetail(
      trainNum: trainNum,
      bureau: (d['bureau'] ?? '') as String,
      bureauShortName: (d['bureauShortName'] ?? '') as String,
      car: (d['car'] ?? '') as String,
      carOwner: (d['carOwner'] ?? '') as String,
      runner: (d['runner'] ?? '') as String,
      numberFull: (d['numberFull'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      numberKind: (d['numberKind'] ?? '').toString(),
      rundays: (d['rundays'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      spend: (d['spend'] as num? ?? 0).toInt(),
      stops: stops,
      diagram: diagram,
      diagramType: diagramType,
      v1ComplementFailed: v1Failed,
    );
  }

  /// 离线链路（SQLite 直查）
  Future<TrainDetail> fetchOffline(String trainNum) async {
    final db = offlineDb;
    if (db == null) throw const TrainNotFoundException('offline-db-unavailable');
    final rows = await db.rawQuery(
      "SELECT * FROM trains WHERE number='${trainNum.replaceAll("'", "''")}'",
    );
    if (rows.isEmpty) throw TrainNotFoundException(trainNum);
    final t = TrainRow.fromMap(rows.first);
    final numberFull = t.numberFull.cast<String>();
    return TrainDetail(
      trainNum: trainNum,
      bureau: '',
      bureauShortName: t.bureauName,
      car: t.car,
      carOwner: '',
      runner: t.runner,
      numberFull: numberFull,
      numberKind: numberFull.isNotEmpty ? numberFull.first[0] : '',
      rundays: const [],
      spend: 0,
      stops: [
        for (final raw in t.timetable)
          if (raw is Map)
            () {
              final s = Map<String, dynamic>.from(raw);
              return TrainStopDetail(
                station: (s['station'] ?? '').toString(),
                stationTelecode: (s['stationTelecode'] ?? '').toString(),
                trainCode: (s['trainCode'] ?? '').toString(),
                arrive: (s['arrive'] ?? '-').toString(),
                depart: (s['depart'] ?? '-').toString(),
                day: (s['day'] as num? ?? 0).toInt(),
                distance: (s['distance'] ?? '-').toString(),
                speed: (s['speed'] as num? ?? 0).toInt(),
              );
            }(),
      ],
      diagram: t.diagram,
      diagramType: t.diagramType,
      fromOfflineDb: true,
    );
  }

  /// 把明细转为状态机可直接消费的 TripTimetable
  TripTimetable toTimetable(TrainDetail d) => TripTimetable(
        trainNum: d.trainNum,
        stops: [
          for (final s in d.stops)
            TripStop(
              station: s.station,
              telecode: s.stationTelecode,
              arrive: s.arrive == '-' ? null : s.arrive,
              depart: s.depart == '-' ? null : s.depart,
              day: s.day,
            ),
        ],
      );
}
