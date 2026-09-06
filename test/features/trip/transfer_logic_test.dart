// test/features/trip/transfer_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/trip/transfer_logic.dart';

void main() {
  group('同站换乘', () {
    test('间隔 < 20min → 换乘紧张', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G101', departureStation: '北京南', arrivalStation: '上海虹桥', departAbsMinutes: 390, arriveAbsMinutes: 684),
        const TripLeg(trainNum: 'G2', departureStation: '上海虹桥', arrivalStation: '杭州东', departAbsMinutes: 703, arriveAbsMinutes: 800),
      );
      expect(a.type, TransferType.sameStation);
      expect(a.gapMinutes, 19);
      expect(a.warning, '换乘紧张');
    });
    test('间隔 = 20min → 不告警（边界不含）', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G101', departureStation: '北京南', arrivalStation: '上海虹桥', departAbsMinutes: 390, arriveAbsMinutes: 684),
        const TripLeg(trainNum: 'G2', departureStation: '上海虹桥', arrivalStation: '杭州东', departAbsMinutes: 704, arriveAbsMinutes: 800),
      );
      expect(a.type, TransferType.sameStation);
      expect(a.warning, isNull);
    });
  });

  group('同城异站（12306 同城组）', () {
    String? cityOf(String s) => (s == '上海虹桥' || s == '上海南' || s == '上海') ? '上海市' : null;
    test('同组且 < 75min → 异站换乘警示', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G101', departureStation: '北京南', arrivalStation: '上海虹桥', departAbsMinutes: 390, arriveAbsMinutes: 684),
        const TripLeg(trainNum: 'K75', departureStation: '上海南', arrivalStation: '嘉兴', departAbsMinutes: 758, arriveAbsMinutes: 900),
        cityOf: cityOf,
      );
      expect(a.type, TransferType.sameCity);
      expect(a.warning, '异站换乘 请快速通行 为安检 检票留足大于15分钟时间');
    });
    test('同组但 ≥ 75min → 仅普通接续提示', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G101', departureStation: '北京南', arrivalStation: '上海虹桥', departAbsMinutes: 390, arriveAbsMinutes: 684),
        const TripLeg(trainNum: 'K75', departureStation: '上海南', arrivalStation: '嘉兴', departAbsMinutes: 760, arriveAbsMinutes: 900),
        cityOf: cityOf,
      );
      expect(a.type, TransferType.sameCity);
      expect(a.warning, isNull);
    });
    test('不同组 → plainConnection', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G101', departureStation: '北京南', arrivalStation: '上海虹桥', departAbsMinutes: 390, arriveAbsMinutes: 684),
        const TripLeg(trainNum: 'G7', departureStation: '南京南', arrivalStation: '武汉', departAbsMinutes: 760, arriveAbsMinutes: 900),
        cityOf: cityOf,
      );
      expect(a.type, TransferType.plainConnection);
    });
  });

  group('同车接续（车次号相同+到达日==出发日）', () {
    test('命中 → 到站前 10min 提示换座', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G1202', departureStation: 'A', arrivalStation: 'B', departAbsMinutes: 300, arriveAbsMinutes: 600),
        const TripLeg(trainNum: 'G1202', departureStation: 'B', arrivalStation: 'C', departAbsMinutes: 660, arriveAbsMinutes: 800),
      );
      expect(a.type, TransferType.sameTrain);
      expect(a.message, '同车接续，请确认是否需要换座');
      expect(a.promptAtAbsMinutes, 590);
    });
    test('到达日≠出发日 → 退化为同站换乘', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G1202', departureStation: 'A', arrivalStation: 'B', departAbsMinutes: 300, arriveAbsMinutes: 600),
        const TripLeg(trainNum: 'G1202', departureStation: 'B', arrivalStation: 'C', departAbsMinutes: 660, arriveAbsMinutes: 800, departDay: 1),
      );
      expect(a.type, TransferType.sameStation);
    });
  });

  group('最大间隔断开', () {
    test('默认 18h：超过 → none 断开', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G1', departureStation: 'A', arrivalStation: 'B', departAbsMinutes: 300, arriveAbsMinutes: 600),
        const TripLeg(trainNum: 'G2', departureStation: 'B', arrivalStation: 'C', departAbsMinutes: 600 + 18 * 60 + 1, arriveAbsMinutes: 2000),
      );
      expect(a.type, TransferType.none);
      expect(a.message, contains('断开'));
    });
    test('用户自定义上限 24h：19h 不断开', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G1', departureStation: 'A', arrivalStation: 'B', departAbsMinutes: 300, arriveAbsMinutes: 600),
        const TripLeg(trainNum: 'G2', departureStation: 'B', arrivalStation: 'C', departAbsMinutes: 600 + 19 * 60, arriveAbsMinutes: 2000),
        maxTransferHours: 24,
      );
      expect(a.type, TransferType.sameStation);
    });
  });

  group('非法间隔', () {
    test('时间重叠（gap<0）→ none', () {
      final a = evaluateTransfer(
        const TripLeg(trainNum: 'G1', departureStation: 'A', arrivalStation: 'B', departAbsMinutes: 300, arriveAbsMinutes: 600),
        const TripLeg(trainNum: 'G2', departureStation: 'B', arrivalStation: 'C', departAbsMinutes: 500, arriveAbsMinutes: 700),
      );
      expect(a.type, TransferType.none);
      expect(a.gapMinutes, -1);
    });
  });

  group('用户设置校验', () {
    test('clampMaxTransferHours 边界', () {
      expect(clampMaxTransferHours(0), 1);
      expect(clampMaxTransferHours(-5), 1);
      expect(clampMaxTransferHours(18), 18);
      expect(clampMaxTransferHours(25), 24);
      expect(clampMaxTransferHours(100), 24);
    });
  });
}
