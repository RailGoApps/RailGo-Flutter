// 行程库加密：SM4 落盘（防磁盘提取）+ 旧明文透明迁移 + 损坏容灾
// + 仓储层（loadTripBoard 状态机/接续、add/remove、StoredTrip JSON 往返）
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/utils/clock.dart';
import 'package:railgo/core/security/key_service.dart';
import 'package:railgo/features/trip/trip_state_machine.dart';
import 'package:railgo/features/trip/trip_store.dart';
import 'package:railgo/features/trip/transfer_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedKey implements Sm4KeySource {
  const _FixedKey(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> obtain() async => bytes;
}

class _BrokenKey implements Sm4KeySource {
  @override
  Future<Uint8List> obtain() async {
    throw StateError('keystore broken');
  }
}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

StoredTrip _trip() => const StoredTrip(
      id: 't1',
      trainNum: 'G1234',
      dateYmd: '20260925',
      stops: [
        TripStop(
          station: '上海虹桥',
          telecode: 'AOH',
          depart: '12:00',
        ),
        TripStop(
          station: '北京南',
          telecode: 'VNP',
          arrive: '13:30',
        ),
      ],
    );

StoredTrip _trip2() => const StoredTrip(
      id: 't2',
      trainNum: 'G5678',
      dateYmd: '20260925',
      stops: [
        TripStop(station: '北京南', telecode: 'VNP', depart: '14:30'),
        TripStop(station: '南京南', telecode: 'NKH', arrive: '15:30'),
      ],
      seat: SeatInfo(carNo: '07', seatNo: '12F', seatClass: SeatClass.second),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('加密往返：落盘无明文（车次/车站不可 grep），读回完整', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(
      prefs,
      keySource: _FixedKey(
        Uint8List.fromList(List<int>.generate(16, (i) => i * 7)),
      ),
    );
    await storage.saveAll([_trip()]);
    final raw = prefs.getString('railgo.trips.v1')!;
    expect(raw.startsWith('['), isFalse); // 非旧明文
    expect(raw.contains('G1234'), isFalse);
    expect(raw.contains('上海虹桥'), isFalse);

    final loaded = await storage.loadAll();
    expect(loaded.length, 1);
    expect(loaded.first.trainNum, 'G1234');
    expect(loaded.first.stops.first.station, '上海虹桥');
    expect(loaded.first.dateYmd, '20260925');
  });

  test('旧明文自动可读 → 下次保存即迁移为密文', () async {
    const plain =
        '[{"id":"t1","trainNum":"G1234","date":"20260925","stops":'
        '[{"station":"上海虹桥","telecode":"AOH","arrive":null,'
        '"depart":"08:00","day":0},'
        '{"station":"北京南","telecode":"VNP","arrive":"13:30",'
        '"depart":null,"day":0}]}]';
    SharedPreferences.setMockInitialValues({
      'railgo.trips.v1': plain,
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(
      prefs,
      keySource: _FixedKey(
        Uint8List.fromList(List<int>.generate(16, (i) => 255 - i)),
      ),
    );

    // 明文兼容读取
    final legacy = await storage.loadAll();
    expect(legacy.first.trainNum, 'G1234');

    // 保存后自动加密
    await storage.saveAll(legacy);
    final raw = prefs.getString('railgo.trips.v1')!;
    expect(raw.startsWith('['), isFalse);
    expect(raw.contains('G1234'), isFalse);
  });

  test('密文损坏 → 容灾返回空（不崩）', () async {
    SharedPreferences.setMockInitialValues({
      'railgo.trips.v1': 'not-valid-ciphertext!!',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(
      prefs,
      keySource: _FixedKey(
        Uint8List.fromList(List<int>.generate(16, (i) => i)),
      ),
    );
    expect(await storage.loadAll(), isEmpty);
  });

  test('密钥源不可用 → StateError 上抛（fail-closed，不吞成空板）', () async {
    SharedPreferences.setMockInitialValues({
      'railgo.trips.v1': 'AAAA', // 密文形态，触发解密路径
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(prefs, keySource: _BrokenKey());
    await expectLater(storage.loadAll(), throwsA(isA<StateError>()));
  });

  test('无密钥源时保持明文兼容（测试/极端降级路径）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(prefs);
    await storage.saveAll([_trip()]);
    expect(prefs.getString('railgo.trips.v1')!.contains('G1234'), isTrue);
  });

  test('密文形态 + 无密钥源 → 解密失败被容灾吞掉（空表不崩）', () async {
    SharedPreferences.setMockInitialValues({
      'railgo.trips.v1': 'QUJDREVG', // Base64 形态但未注入密钥源
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsTripStorage(prefs); // keySource == null
    expect(await storage.loadAll(), isEmpty);
  });

  group('TripRepository（固定时钟）', () {
    // UTC 02:30 == 上海 10:30（630 分）；当日行程 12:00 发车（发车前 2h 内）
    final clock = _FixedClock(DateTime.utc(2026, 9, 25, 2, 30));

    Future<TripRepository> repo(
        SharedPreferences prefs, Sm4KeySource key) async {
      final storage = PrefsTripStorage(prefs, keySource: key);
      await storage.saveAll([_trip(), _trip2()]);
      return TripRepository(storage: storage, clock: clock);
    }

    test('loadTripBoard：状态机评估 + 跨行程接续建议', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final r = await repo(
          prefs, _FixedKey(Uint8List.fromList(List.generate(16, (i) => i))));
      final board = await r.loadTripBoard();
      expect(board.length, 2);
      // G1234 12:00 发车（720），上海时区现在 630 → 发车前 2h 内
      expect(board.first.status.phase, TripPhase.departingSoon);
      // G1234 13:30 到北京南 → G5678 14:30 北京南发车：同站 60 分钟接续
      expect(board.first.transferToNext, isNotNull);
      expect(board.first.transferToNext!.type, TransferType.sameStation);
      // 后程无下一程 → 无建议
      expect(board.last.transferToNext, isNull);
    });

    test('add / remove：加密落盘与删除', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final key =
          _FixedKey(Uint8List.fromList(List.generate(16, (i) => 9 - i)));
      final storage = PrefsTripStorage(prefs, keySource: key);
      final r = TripRepository(storage: storage, clock: clock);
      await r.add(_trip());
      expect((await r.loadTripBoard()).length, 1);
      await r.add(_trip2());
      expect((await r.loadTripBoard()).length, 2);
      await r.remove('t1');
      final board = await r.loadTripBoard();
      expect(board.length, 1);
      expect(board.first.trip.trainNum, 'G5678');
      expect(prefs.getString('railgo.trips.v1')!.contains('G1234'), isFalse);
    });

    test('StoredTrip JSON 往返（含座位；非法席位枚举回退 second）', () {
      final j = _trip2().toJson();
      expect(j['seat']!['class'], 'second');
      final back = StoredTrip.fromJson(j);
      expect(back.seat!.seatNo, '12F');
      expect(back.seat!.seatClass, SeatClass.second);
      expect(back.asTimetable.stops.length, 2);

      final broken = Map<String, dynamic>.from(j);
      broken['seat'] = {
        'carNo': '01',
        'seatNo': '01A',
        'class': 'not-a-class',
      };
      expect(StoredTrip.fromJson(broken).seat!.seatClass, SeatClass.second);
    });
  });
}
