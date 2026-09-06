// lib/features/trip/trip_store.dart
//
// 行程存储与聚合（基线 route 页语义 + 新状态机/接续能力）：
//   持久化：shared_preferences JSON 数组（与原项目 storage 行程一致量级）
//   聚合：每趟行程 → TripStateMachine.evaluate + 相邻行程 evaluateTransfer
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/railgo_time.dart';
import 'transfer_logic.dart';
import 'trip_state_machine.dart';

class StoredTrip {
  const StoredTrip({
    required this.id,
    required this.trainNum,
    required this.dateYmd,
    required this.stops,
    this.seat,
  });

  final String id;
  final String trainNum;

  /// 发车日 yyyymmdd（上海时区）
  final String dateYmd;
  final List<TripStop> stops;
  final SeatInfo? seat;

  Map<String, dynamic> toJson() => {
        'id': id,
        'trainNum': trainNum,
        'date': dateYmd,
        'stops': stops
            .map((s) => {
                  'station': s.station,
                  'telecode': s.telecode,
                  'arrive': s.arrive,
                  'depart': s.depart,
                  'day': s.day,
                })
            .toList(),
        if (seat != null)
          'seat': {'carNo': seat!.carNo, 'seatNo': seat!.seatNo, 'class': seat!.seatClass.name},
      };

  static StoredTrip fromJson(Map<String, dynamic> j) => StoredTrip(
        id: j['id'] as String,
        trainNum: j['trainNum'] as String,
        dateYmd: j['date'] as String,
        stops: (j['stops'] as List<dynamic>)
            .map((s) => TripStop(
                  station: s['station'] as String,
                  telecode: s['telecode'] as String? ?? '',
                  arrive: s['arrive'] as String?,
                  depart: s['depart'] as String?,
                  day: s['day'] as int? ?? 0,
                ))
            .toList(),
        seat: j['seat'] == null
            ? null
            : SeatInfo(
                carNo: j['seat']['carNo'] as String?,
                seatNo: j['seat']['seatNo'] as String?,
                seatClass: SeatClass.values.firstWhere(
                  (c) => c.name == j['seat']['class'],
                  orElse: () => SeatClass.second,
                ),
              ),
      );

  TripTimetable get asTimetable => TripTimetable(trainNum: trainNum, stops: stops);
}

abstract class TripStorage {
  Future<List<StoredTrip>> loadAll();
  Future<void> saveAll(List<StoredTrip> trips);
}

class PrefsTripStorage implements TripStorage {
  PrefsTripStorage(this._prefs);
  final SharedPreferences _prefs;
  static const _kKey = 'railgo.trips.v1';

  @override
  Future<List<StoredTrip>> loadAll() async {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => StoredTrip.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const []; // 损坏 → 空（容灾，勿崩）
    }
  }

  @override
  Future<void> saveAll(List<StoredTrip> trips) => _prefs.setString(
        _kKey,
        jsonEncode(trips.map((t) => t.toJson()).toList()),
      );
}

class TripWithStatus {
  const TripWithStatus({
    required this.trip,
    required this.status,
    this.transferToNext,
  });

  final StoredTrip trip;
  final TripStatus status;

  /// 与下一趟行程的接续建议（无下一趟或断开时为 null）
  final TransferAdvice? transferToNext;
}

class TripRepository {
  TripRepository({
    required this.storage,
    this.clock = const SystemClock(),
    this.maxTransferHours = kDefaultMaxTransferHours,
    this.cityOf,
  });

  final TripStorage storage;
  final AppClock clock;
  final int maxTransferHours;
  final CityGroupResolver? cityOf;
  final _machine = TripStateMachine();

  /// 当前分钟数（相对各行程发车日零点；按上海时区计算今天零点经过的分钟 + 跨日偏移）
  int nowMinutesSince(String dateYmd) {
    final now = clock.now();
    final sh = DateTime(now.toUtc().add(kShanghaiOffset).year, //
        now.toUtc().add(kShanghaiOffset).month,
        now.toUtc().add(kShanghaiOffset).day);
    final y = int.parse(dateYmd.substring(0, 4));
    final m = int.parse(dateYmd.substring(4, 6));
    final d = int.parse(dateYmd.substring(6, 8));
    final base = DateTime(y, m, d);
    final diffDays = sh.difference(base).inDays;
    final shNow = now.toUtc().add(kShanghaiOffset);
    final minuteOfDay = shNow.hour * 60 + shNow.minute;
    return diffDays * 1440 + minuteOfDay;
  }

  Future<List<TripWithStatus>> loadTripBoard() async {
    final trips = (await storage.loadAll())..sort((a, b) => a.dateYmd.compareTo(b.dateYmd));
    final out = <TripWithStatus>[];
    for (var i = 0; i < trips.length; i++) {
      final t = trips[i];
      final status = _machine.evaluate(
        timetable: t.asTimetable,
        nowMinutes: nowMinutesSince(t.dateYmd),
      );
      TransferAdvice? advice;
      if (i + 1 < trips.length) {
        final next = trips[i + 1];
        final prevLast = t.stops.lastWhere((s) => s.arrive != null, orElse: () => t.stops.last);
        final nextFirst = next.stops.first;
        final prevArrive = absoluteMinutes(day: prevLast.day, hhmm: prevLast.arrive);
        // 关键：后程发车时刻须叠加两行程发车日的天数差，否则跨日接续会漏加 1440×N
        final dateDeltaDays = _daysBetween(t.dateYmd, next.dateYmd);
        final nextDepart = absoluteMinutes(day: dateDeltaDays, hhmm: nextFirst.depart);
        if (prevArrive != null && nextDepart != null) {
          advice = evaluateTransfer(
            TripLeg(
              trainNum: t.trainNum,
              departureStation: t.stops.first.station,
              arrivalStation: prevLast.station,
              departAbsMinutes: 0, // 同板内仅比较间隙，出发时刻不参与
              arriveAbsMinutes: prevArrive,
              arriveDay: prevLast.day,
            ),
            TripLeg(
              trainNum: next.trainNum,
              departureStation: nextFirst.station,
              arrivalStation: next.stops.last.station,
              departAbsMinutes: nextDepart,
              arriveAbsMinutes: 0,
              departDay: 0,
            ),
            cityOf: cityOf,
            maxTransferHours: maxTransferHours,
          );
          if (advice.type == TransferType.none) advice = null;
        }
      }
      out.add(TripWithStatus(trip: t, status: status, transferToNext: advice));
    }
    return out;
  }

  /// 两个 yyyymmdd 的天数差（b - a）
  static int _daysBetween(String aYmd, String bYmd) {
    DateTime parse(String s) => DateTime(
          int.parse(s.substring(0, 4)),
          int.parse(s.substring(4, 6)),
          int.parse(s.substring(6, 8)),
        );
    return parse(bYmd).difference(parse(aYmd)).inDays;
  }

  Future<void> add(StoredTrip trip) async {
    final all = await storage.loadAll();
    all.add(trip);
    await storage.saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await storage.loadAll();
    all.removeWhere((t) => t.id == id);
    await storage.saveAll(all);
  }
}
