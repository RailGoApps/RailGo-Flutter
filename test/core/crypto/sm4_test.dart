// test/core/crypto/sm4_test.dart
//
// SM4 单元测试：GB/T 32907-2016 标准向量 + PKCS7 边界 + CBC/ECB 一致性 + 中文往返。
// （Phase 3 CI 覆盖率门槛模块之一：lib/core/crypto）
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/crypto/sm4.dart';

void main() {
  // GB/T 32907-2016 附录 A 标准算例
  const stdKeyHex = '0123456789abcdeffedcba9876543210';
  const stdPlainHex = '0123456789abcdeffedcba9876543210';
  const stdCipherHex = '681edf34d206965e86b3e94f536e4246';

  group('GB/T 32907-2016 标准向量', () {
    test('单块加密符合国标示例', () {
      final engine = Sm4Engine(Sm4Cipher.hexToBytes(stdKeyHex));
      final out = engine.encryptBlock(Sm4Cipher.hexToBytes(stdPlainHex));
      expect(out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          stdCipherHex);
    });

    test('单块解密可逆', () {
      final engine = Sm4Engine(Sm4Cipher.hexToBytes(stdKeyHex));
      final out = engine.decryptBlock(Sm4Cipher.hexToBytes(stdCipherHex));
      expect(out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          stdPlainHex);
    });
  });

  group('参数校验', () {
    test('密钥长度必须 16 字节', () {
      expect(() => Sm4Engine(List<int>.filled(15, 0)), throwsArgumentError);
      expect(() => Sm4Engine(List<int>.filled(17, 0)), throwsArgumentError);
    });

    test('分组长度必须 16 字节', () {
      final engine = Sm4Engine(Sm4Cipher.hexToBytes(stdKeyHex));
      expect(() => engine.encryptBlock(List<int>.filled(15, 0)),
          throwsArgumentError);
    });

    test('IV 长度必须 16 字节', () {
      expect(
        () => Sm4Cipher(Sm4Engine(Sm4Cipher.hexToBytes(stdKeyHex)),
            iv: Uint8List(8)),
        throwsArgumentError,
      );
    });
  });

  group('PKCS7 填充往返', () {
    final key = Sm4Cipher.hexToBytes(stdKeyHex);

    test('空串', () {
      final c = Sm4Cipher(Sm4Engine(key), mode: Sm4Mode.ecb);
      expect(c.decrypt(c.encrypt(<int>[])), isEmpty);
    });

    test('1 / 15 / 16 / 17 / 32 字节边界', () {
      final c = Sm4Cipher(Sm4Engine(key), mode: Sm4Mode.ecb);
      for (final len in [1, 15, 16, 17, 32]) {
        final data = List<int>.generate(len, (i) => i % 256);
        final enc = c.encrypt(data);
        expect(enc.length % 16, 0, reason: 'len=$len');
        expect(enc.length >= len, isTrue);
        expect(c.decrypt(enc), data);
      }
    });

    test('篡改填充字节应抛出 FormatException', () {
      final c = Sm4Cipher(Sm4Engine(key), mode: Sm4Mode.ecb);
      final enc = c.encrypt(<int>[1, 2, 3]);
      enc[enc.length - 1] = (enc.last + 1) % 256;
      expect(() => c.decrypt(enc), throwsFormatException);
    });
  });

  group('ECB / CBC 模式', () {
    final key = Sm4Cipher.hexToBytes(stdKeyHex);

    test('CBC 相同明文不同 IV 密文不同（语义安全基础）', () {
      final plain = utf8.encode('RailGo SM4 CBC 测试数据');
      final c1 =
          Sm4Cipher(Sm4Engine(key), iv: Uint8List.fromList(List.filled(16, 0)));
      final c2 =
          Sm4Cipher(Sm4Engine(key), iv: Uint8List.fromList(List.filled(16, 1)));
      final e1 = c1.encrypt(plain);
      final e2 = c2.encrypt(plain);
      expect(e1, isNot(equals(e2)));
      expect(c1.decrypt(e1), plain);
      expect(c2.decrypt(e2), plain);
    });

    test('ECB 相同明文块密文相同（已知弱点，仅作对照）', () {
      final plain = utf8.encode('0123456789abcdef0123456789abcdef'); // 两个相同块
      final c = Sm4Cipher(Sm4Engine(key), mode: Sm4Mode.ecb);
      final enc = c.encrypt(plain);
      final b1 = enc.sublist(0, 16);
      final b2 = enc.sublist(16, 32);
      expect(b1, equals(b2));
    });

    test('CBC 头 16 字节为 IV，可跨实例解密', () {
      final cEnc = Sm4Cipher(Sm4Engine(key));
      final enc = cEnc.encrypt(utf8.encode('跨实例解密'));
      final iv = Uint8List.fromList(enc.sublist(0, 16));
      final cDec = Sm4Cipher(Sm4Engine(key), iv: iv);
      expect(cDec.decrypt(enc), utf8.encode('跨实例解密'));
    });
  });

  group('字符串便捷接口（证件 JSON 场景）', () {
    test('Base64 往返（含中文/emoji）', () {
      final c = sm4CipherFromHexKey(stdKeyHex);
      const sample = '{"name":"张三","id":"110101199003077758","note":"🚄证件"}';
      final enc = c.encryptStringToBase64(sample);
      expect(c.decryptStringFromBase64(enc), sample);
    });

    test('错误密钥解密：要么抛 FormatException，要么绝不还原出原文', () {
      final c1 = sm4CipherFromHexKey('00000000000000000000000000000001');
      final c2 = sm4CipherFromHexKey('00000000000000000000000000000002');
      final enc = c1.encryptStringToBase64('secret');
      Object? thrown;
      String? out;
      try {
        out = c2.decryptStringFromBase64(enc);
      } catch (e) {
        thrown = e;
      }
      // 填充校验有极小概率恰好通过，此时也必须得不到原文
      expect(thrown != null || out != 'secret', isTrue);
    });

    test('hexToBytes 奇数长度抛出', () {
      expect(() => Sm4Cipher.hexToBytes('abc'), throwsFormatException);
    });
  });
}
