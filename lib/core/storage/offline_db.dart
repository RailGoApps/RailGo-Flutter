// lib/core/storage/offline_db.dart
//
// 离线数据库（任务书 §3.1 容灾：SQLite 损坏 → 内存缓存兜底）。
// Schema 对齐基线 §4.5：trains / stations 两表，JSON 字段入库、读取反序列化。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class TrainRow {
  const TrainRow({
    required this.code,
    required this.numberFull,
    required this.numberKind,
    required this.bureauName,
    required this.car,
    required this.runner,
    required this.timetable,
    required this.diagram,
    required this.diagramType,
  });

  factory TrainRow.fromMap(Map<String, Object?> m) => TrainRow(
        code: m['code'] as String? ?? '',
        numberFull: _decodeList(m['numberFull']),
        numberKind: m['numberKind'] as String? ?? '',
        bureauName: m['bureauName'] as String? ?? '',
        car: m['car'] as String? ?? '',
        runner: m['runner'] as String? ?? '',
        timetable: _decodeList(m['timetable']),
        diagram: _decodeList(m['diagram']),
        diagramType: m['diagramType'] as String? ?? '',
      );

  final String code;
  final List<dynamic> numberFull;
  final String numberKind;
  final String bureauName;
  final String car;
  final String runner;
  final List<dynamic> timetable;
  final List<dynamic> diagram;
  final String diagramType;

  static List<dynamic> _decodeList(Object? v) {
    if (v is List) return v;
    if (v is String) {
      try {
        return jsonDecode(v) as List<dynamic>;
      } catch (_) {
        return const <dynamic>[];
      }
    }
    return const <dynamic>[];
  }
}

/// 纯函数：构造车次号 LIKE 预查 SQL（基线 train/query.vue 离线分支语义）
/// 数字开头 → 同时匹配 `"_<kw>"` 与 `"<kw>"`（复车次下划线变体）；否则模糊匹配。
List<String> buildTrainPreselectSql(String keyword) {
  final kw = keyword.trim();
  if (kw.isEmpty) return const [];
  final esc = kw.replaceAll("'", "''");
  if (kw.codeUnitAt(0) >= 0x30 && kw.codeUnitAt(0) <= 0x39) {
    return [
      "SELECT code, numberFull, timetable FROM trains WHERE numberFull LIKE '%\"_$esc\"%' OR numberFull LIKE '%\"$esc\"%'",
    ];
  }
  return ["SELECT code, numberFull, timetable FROM trains WHERE numberFull LIKE '%$esc%'"];
}

abstract class OfflineDb {
  Future<List<Map<String, Object?>>> rawQuery(String sql);
  Future<void> open();
  Future<void> close();
  bool get isMemoryFallback;
}

class SqliteOfflineDb implements OfflineDb {
  SqliteOfflineDb({required this.path});

  final String path;
  Database? _db;
  bool _memoryFallback = false;
  final List<Map<String, Object?>> _memRows = [];

  @override
  bool get isMemoryFallback => _memoryFallback;

  @override
  Future<void> open() async {
    try {
      _db = await openDatabase(path, readOnly: true);
    } catch (_) {
      // 容灾：库文件损坏/缺失 → 内存兜底（仅能服务已缓存数据，需提示用户重新下载）
      _memoryFallback = true;
      _db = null;
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql) async {
    final db = _db;
    if (db == null) return List<Map<String, Object?>>.from(_memRows);
    try {
      return await db.rawQuery(sql);
    } catch (_) {
      _memoryFallback = true;
      return List<Map<String, Object?>>.from(_memRows);
    }
  }

  /// 注入内存兜底数据（下载完成或恢复时调用）
  void seedMemoryRows(List<Map<String, Object?>> rows) {
    _memRows
      ..clear()
      ..addAll(rows);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// 离线模式下车次查询 → TripTimetable（供状态机使用）
TripTimetableRow? timetableFromRawRow(Map<String, Object?> row) {
  final timetable = TrainRow.fromMap(row).timetable;
  if (timetable.isEmpty) return null;
  final stops = <({String station, String telecode, String? arrive, String? depart})>[];
  for (final s in timetable) {
    if (s is! Map) continue;
    stops.add((
      station: s['station'] as String? ?? '',
      telecode: s['stationTelecode'] as String? ?? '',
      arrive: s['arrive'] as String?,
      depart: s['depart'] as String?,
    ));
  }
  if (stops.length < 2) return null;
  return TripTimetableRow(stops: stops, numberFull: TrainRow.fromMap(row).numberFull.cast<String>());
}

class TripTimetableRow {
  const TripTimetableRow({required this.stops, required this.numberFull});
  final List<({String station, String telecode, String? arrive, String? depart})> stops;
  final List<String> numberFull;
}
