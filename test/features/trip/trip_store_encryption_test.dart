// 行程库加密：SM4 落盘（防磁盘提取）+ 旧明文透明迁移 + 损坏容灾
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/key_service.dart';
import 'package:railgo/features/trip/trip_state_machine.dart';
import 'package:railgo/features/trip/trip_store.dart';
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

StoredTrip _trip() => const StoredTrip(
      id: 't1',
      trainNum: 'G1234',
      dateYmd: '20260925',
      stops: [
        TripStop(
          station: '上海虹桥',
          telecode: 'AOH',
          depart: '08:00',
        ),
        TripStop(
          station: '北京南',
          telecode: 'VNP',
          arrive: '13:30',
        ),
      ],
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
    const plain = '[{"id":"t1","trainNum":"G1234","date":"20260925","stops":'
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
}
