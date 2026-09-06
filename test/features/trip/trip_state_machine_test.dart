// test/features/trip/trip_state_machine_test.dart
//
// 行程状态机单元测试（Phase 3 CI 覆盖率门槛模块之一：lib/features/trip）
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/trip/trip_state_machine.dart';

TripTimetable g1Like() => const TripTimetable(
      trainNum: 'G1',
      stops: [
        TripStop(station: '北京南', telecode: 'VNP', depart: '06:30'),
        TripStop(
            station: '沧州西', telecode: 'CBP', arrive: '07:18', depart: '07:20'),
        TripStop(station: '上海虹桥', telecode: 'AOH', arrive: '11:24'),
      ],
    );

// 参考绝对分钟：depart1=390, arrive2=438, depart2=440, arrive3=684
void main() {
  final machine = TripStateMachine();

  group('数据合法性', () {
    test('少于 2 站 → finished(invalid_timetable)', () {
      final s = machine.evaluate(
        timetable: const TripTimetable(
            trainNum: 'X',
            stops: [TripStop(station: 'A', telecode: 'AAA', depart: '08:00')]),
        nowMinutes: 0,
      );
      expect(s.phase, TripPhase.finished);
      expect(s.reason, 'invalid_timetable');
    });
    test('首站缺出发时刻 → finished(missing_first_depart)', () {
      final s = machine.evaluate(
        timetable: const TripTimetable(trainNum: 'X', stops: [
          TripStop(station: 'A', telecode: 'AAA'),
          TripStop(station: 'B', telecode: 'BBB', arrive: '09:00'),
        ]),
        nowMinutes: 0,
      );
      expect(s.phase, TripPhase.finished);
      expect(s.reason, 'missing_first_depart');
    });
  });

  group('四状态流转（G1 型白班车）', () {
    test('发车前 2h 之外 → idle，nextChange = 发车-2h', () {
      final s = machine.evaluate(timetable: g1Like(), nowMinutes: 269);
      expect(s.phase, TripPhase.idle);
      expect(s.nextChangeAtMinutes, 270);
    });
    test('恰为发车前 2h → departingSoon（边界含）', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 270).phase,
          TripPhase.departingSoon);
    });
    test('发车前 1 分钟 → departingSoon', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 389).phase,
          TripPhase.departingSoon);
    });
    test('发车时刻 → 进入运行 nextStation', () {
      final s = machine.evaluate(timetable: g1Like(), nowMinutes: 390);
      expect(s.phase, TripPhase.nextStation);
      expect(s.nextStopIndex, 1);
    });
    test('距到站 18 分钟 → nextStation，nextChange=到站-15', () {
      final s = machine.evaluate(timetable: g1Like(), nowMinutes: 420);
      expect(s.phase, TripPhase.nextStation);
      expect(s.nextChangeAtMinutes, 423);
    });
    test('距到站 15 分钟（边界）→ arrivingSoon', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 423).phase,
          TripPhase.arrivingSoon);
    });
    test('到站前 1 分钟 → arrivingSoon', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 437).phase,
          TripPhase.arrivingSoon);
    });
    test('到站时刻 → stopped（区间 [438,440]）', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 438).phase,
          TripPhase.stopped);
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 440).phase,
          TripPhase.stopped);
    });
    test('出发后 → 重新进入 nextStation（下一区间）', () {
      final s = machine.evaluate(timetable: g1Like(), nowMinutes: 441);
      expect(s.phase, TripPhase.nextStation);
      expect(s.nextStopIndex, 2);
    });
    test('终到站到达 → finished', () {
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 684).phase,
          TripPhase.finished);
      expect(machine.evaluate(timetable: g1Like(), nowMinutes: 700).phase,
          TripPhase.finished);
    });
  });

  group('跨日行程（夜车）', () {
    const night = TripTimetable(
      trainNum: 'Z98',
      stops: [
        TripStop(station: 'A', telecode: 'AAA', depart: '22:00'),
        TripStop(
            station: 'B', telecode: 'BBB', arrive: '23:30', depart: '23:50'),
        TripStop(
            station: 'C',
            telecode: 'CCC',
            arrive: '01:10',
            depart: '01:12',
            day: 1),
        TripStop(station: 'D', telecode: 'DDD', arrive: '03:00', day: 1),
      ],
    );
    test('次日运行中 → nextStation', () {
      // B 出发 1430，C 到达 1450+60=1510
      final s = machine.evaluate(timetable: night, nowMinutes: 1450);
      expect(s.phase, TripPhase.nextStation);
      expect(s.nextStopIndex, 2);
    });
    test('次日临近到达 → arrivingSoon', () {
      expect(machine.evaluate(timetable: night, nowMinutes: 1500).phase,
          TripPhase.arrivingSoon);
    });
    test('终到（次日 03:00=1620）→ finished', () {
      expect(machine.evaluate(timetable: night, nowMinutes: 1620).phase,
          TripPhase.finished);
    });
  });

  group('脏数据防御（红队：不得死循环/崩溃）', () {
    test('中间站缺 arrive → 以 depart 为界回退 nextStation', () {
      const dirty = TripTimetable(
        trainNum: 'K0000',
        stops: [
          TripStop(station: 'A', telecode: 'AAA', depart: '08:00'),
          TripStop(station: 'B', telecode: 'BBB', depart: '10:00'), // 无 arrive
          TripStop(station: 'C', telecode: 'CCC', arrive: '12:00'),
        ],
      );
      final s = machine.evaluate(timetable: dirty, nowMinutes: 500);
      expect(s.phase, TripPhase.nextStation);
      expect(s.reason, 'missing_arrive_fallback');
    });
    test('now 远超终到 → finished 且不再变化', () {
      final s = machine.evaluate(timetable: g1Like(), nowMinutes: 100000);
      expect(s.phase, TripPhase.finished);
      expect(s.nextChangeAtMinutes, isNull);
    });
    test('全部时刻缺失的站不阻塞推进', () {
      const weird = TripTimetable(
        trainNum: 'X',
        stops: [
          TripStop(station: 'A', telecode: 'AAA', depart: '08:00'),
          TripStop(station: 'B', telecode: 'BBB'), // 全空
          TripStop(station: 'C', telecode: 'CCC', arrive: '10:00'),
        ],
      );
      final s = machine.evaluate(timetable: weird, nowMinutes: 481);
      expect(s.phase, TripPhase.nextStation);
      expect(s.nextStopIndex, 2);
    });
  });
}
