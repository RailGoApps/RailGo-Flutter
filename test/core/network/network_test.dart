// test/core/network/network_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/network/rate_limiter.dart';
import 'package:railgo/core/network/service_registry.dart';
import 'package:railgo/core/security/auth_gate.dart';

void main() {
  group('服务源注册表（基线 §3.1 对齐）', () {
    test('15 个服务 code 全部有元数据', () {
      expect(ServiceCode.all.length, 15);
      for (final code in ServiceCode.all) {
        expect(kServiceCatalog[code], isNotNull, reason: code);
      }
    });
    test('缺省域名与基线一致', () {
      expect(kServiceCatalog[ServiceCode.train]!.defaultBase, 'https://data.railgo.zenglingkun.cn');
      expect(kServiceCatalog[ServiceCode.trainV2]!.defaultBase, 'https://rg-api.zenglingkun.cn');
      expect(kServiceCatalog[ServiceCode.emuRun]!.defaultBase, 'https://emu.railgo.zenglingkun.cn');
      expect(kServiceCatalog[ServiceCode.notice]!.defaultBase, 'https://gateway.zenglingkun.cn');
      expect(kServiceCatalog[ServiceCode.tp]!.defaultBase, 'https://tp.railgo.zenglingkun.cn');
    });
    test('服务发现响应解析（[{code:[{desc,url}]}]）', () {
      final parsed = parseServiceEndpoints([
        {
          'train': [
            {'desc': '主源', 'url': 'https://data.railgo.zenglingkun.cn'},
            {'desc': '镜像', 'url': 'https://mirror.example'},
          ]
        },
        {'station': []},
      ]);
      expect(parsed['train']!.length, 2);
      expect(parsed['train']!.first.url, 'https://data.railgo.zenglingkun.cn');
      expect(parsed['train']!.last.desc, '镜像');
      expect(parsed['station'], isEmpty);
    });
    test('脏数据容错：非 Map 项/缺 url 跳过', () {
      final parsed = parseServiceEndpoints([
        'not-a-map',
        {'x': [{'desc': 1, 'url': null}, 'junk', {'url': 'https://ok'}]},
      ]);
      expect(parsed['x']!.length, 1);
      expect(parsed['x']!.first.url, 'https://ok');
    });
  });

  group('令牌桶与并发闸门', () {
    test('突发后限速生效（不超 burst 立即放行）', () async {
      final bucket = TokenBucket(ratePerSecond: 50, burst: 3);
      final sw = Stopwatch()..start();
      // 前 3 个立即
      await bucket.acquire();
      await bucket.acquire();
      await bucket.acquire();
      expect(sw.elapsedMilliseconds, lessThan(200));
      // 第 4 个需等待
      await bucket.acquire();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(10));
    });

    test('并发闸门串行化超过上限的任务', () async {
      final gate = ConcurrencyGate(2);
      var running = 0;
      var maxRunning = 0;
      Future<void> task() async {
        running++;
        maxRunning = running > maxRunning ? running : maxRunning;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        running--;
      }

      await Future.wait([gate.run(task), gate.run(task), gate.run(task), gate.run(task), gate.run(task)]);
      expect(maxRunning, lessThanOrEqualTo(2));
    });
  });

  group('PIN 哈希（安全层纯逻辑）', () {
    const hasher = PinHasher();
    test('6 位数字格式校验', () {
      expect(PinHasher.isValidPinFormat('123456'), isTrue);
      expect(PinHasher.isValidPinFormat('12345'), isFalse);
      expect(PinHasher.isValidPinFormat('1234567'), isFalse);
      expect(PinHasher.isValidPinFormat('12a456'), isFalse);
    });
    test('同盐同 PIN 哈希一致；不同盐不同哈希', () {
      final h1 = hasher.hash('123456', 'saltA');
      final h2 = hasher.hash('123456', 'saltA');
      final h3 = hasher.hash('123456', 'saltB');
      expect(h1, h2);
      expect(h1, isNot(h3));
      expect(h1.length, 64); // SHA-256 hex
    });
    test('恒时比较', () {
      expect(hasher.fixedTimeEquals('abc', 'abc'), isTrue);
      expect(hasher.fixedTimeEquals('abc', 'abd'), isFalse);
      expect(hasher.fixedTimeEquals('abc', 'abcd'), isFalse);
    });
  });
}
