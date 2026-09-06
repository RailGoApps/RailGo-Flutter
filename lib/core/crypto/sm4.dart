// lib/core/crypto/sm4.dart
//
// 国密 SM4 分组密码（GB/T 32907-2016）纯 Dart 实现。
// 说明：pointycastle 本身未收录 SM4，故此处实现算法本体；
// pointycastle 用于密钥派生（PBKDF2，见 lib/core/security/key_service.dart）。
//
// 提供：
//   Sm4Engine    —— 16 字节分组加/解密原语（ECB 单块）
//   Sm4Cipher    —— 面向字节的填充式加解密（PKCS#7），支持 ECB / CBC
//   sm4HexEncode / sm4HexDecode / sm4Base64... 便捷函数
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const List<int> _kSbox = <int>[
  0xd6, 0x90, 0xe9, 0xfe, 0xcc, 0xe1, 0x3d, 0xb7, 0x16, 0xb6, 0x14, 0xc2, 0x28, 0xfb, 0x2c, 0x05, //
  0x2b, 0x67, 0x9a, 0x76, 0x2a, 0xbe, 0x04, 0xc3, 0xaa, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99,
  0x9c, 0x42, 0x50, 0xf4, 0x91, 0xef, 0x98, 0x7a, 0x33, 0x54, 0x0b, 0x43, 0xed, 0xcf, 0xac, 0x62,
  0xe4, 0xb3, 0x1c, 0xa9, 0xc9, 0x08, 0xe8, 0x95, 0x80, 0xdf, 0x94, 0xfa, 0x75, 0x8f, 0x3f, 0xa6,
  0x47, 0x07, 0xa7, 0xfc, 0xf3, 0x73, 0x17, 0xba, 0x83, 0x59, 0x3c, 0x19, 0xe6, 0x85, 0x4f, 0xa8,
  0x68, 0x6b, 0x81, 0xb2, 0x71, 0x64, 0xda, 0x8b, 0xf8, 0xeb, 0x0f, 0x4b, 0x70, 0x56, 0x9d, 0x35,
  0x1e, 0x24, 0x0e, 0x5e, 0x63, 0x58, 0xd1, 0xa2, 0x25, 0x22, 0x7c, 0x3b, 0x01, 0x21, 0x78, 0x87,
  0xd4, 0x00, 0x46, 0x57, 0x9f, 0xd3, 0x27, 0x52, 0x4c, 0x36, 0x02, 0xe7, 0xa0, 0xc4, 0xc8, 0x9e,
  0xea, 0xbf, 0x8a, 0xd2, 0x40, 0xc7, 0x38, 0xb5, 0xa3, 0xf7, 0xf2, 0xce, 0xf9, 0x61, 0x15, 0xa1,
  0xe0, 0xae, 0x5d, 0xa4, 0x9b, 0x34, 0x1a, 0x55, 0xad, 0x93, 0x32, 0x30, 0xf5, 0x8c, 0xb1, 0xe3,
  0x1d, 0xf6, 0xe2, 0x2e, 0x82, 0x66, 0xca, 0x60, 0xc0, 0x29, 0x23, 0xab, 0x0d, 0x53, 0x4e, 0x6f,
  0xd5, 0xdb, 0x37, 0x45, 0xde, 0xfd, 0x8e, 0x2f, 0x03, 0xff, 0x6a, 0x72, 0x6d, 0x6c, 0x5b, 0x51,
  0x8d, 0x1b, 0xaf, 0x92, 0xbb, 0xdd, 0xbc, 0x7f, 0x11, 0xd9, 0x5c, 0x41, 0x1f, 0x10, 0x5a, 0xd8,
  0x0a, 0xc1, 0x31, 0x88, 0xa5, 0xcd, 0x7b, 0xbd, 0x2d, 0x74, 0xd0, 0x12, 0xb8, 0xe5, 0xb4, 0xb0,
  0x89, 0x69, 0x97, 0x4a, 0x0c, 0x96, 0x77, 0x7e, 0x65, 0xb9, 0xf1, 0x09, 0xc5, 0x6e, 0xc6, 0x84,
  0x18, 0xf0, 0x7d, 0xec, 0x3a, 0xdc, 0x4d, 0x20, 0x79, 0xee, 0x5f, 0x3e, 0xd7, 0xcb, 0x39, 0x48,
];

const List<int> _kFk = <int>[0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc];

const List<int> _kCk = <int>[
  0x00070e15, 0x1c232a31, 0x383f464d, 0x545b6269, //
  0x70777e85, 0x8c939aa1, 0xa8afb6bd, 0xc4cbd2d9,
  0xe0e7eef5, 0xfc030a11, 0x181f262d, 0x343b4249,
  0x50575e65, 0x6c737a81, 0x888f969d, 0xa4abb2b9,
  0xc0c7ced5, 0xdce3eaf1, 0xf8ff060d, 0x141b2229,
  0x30373e45, 0x4c535a61, 0x686f767d, 0x848b9299,
  0xa0a7aeb5, 0xbcc3cad1, 0xd8dfe6ed, 0xf4fb0209,
  0x10171e25, 0x2c333a41, 0x484f565d, 0x646b7279,
];

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;

int _tau(int a) => (_kSbox[(a >>> 24) & 0xff] << 24) | (_kSbox[(a >>> 16) & 0xff] << 16) | (_kSbox[(a >>> 8) & 0xff] << 8) | _kSbox[a & 0xff];

/// 加密轮变换 T = L(τ(·))，L 用于数据
int _tEncrypt(int a) {
  final b = _tau(a);
  return b ^ _rotl32(b, 2) ^ _rotl32(b, 10) ^ _rotl32(b, 18) ^ _rotl32(b, 24);
}

/// 密钥扩展轮变换 T' = L'(τ(·))，L' 用于轮密钥
int _tKey(int a) {
  final b = _tau(a);
  return b ^ _rotl32(b, 13) ^ _rotl32(b, 23);
}

/// SM4 引擎：持有一组轮密钥，可重复加/解密 16 字节块（非线程安全语义，Dart 单线程模型下安全）。
class Sm4Engine {
  Sm4Engine(List<int> key) {
    if (key.length != 16) {
      throw ArgumentError('SM4 key must be 16 bytes (128 bit), got ${key.length}');
    }
    _roundKeys = _expandKey(key);
  }

  late final List<int> _roundKeys;

  static List<int> _expandKey(List<int> key) {
    final mk = <int>[
      (key[0] << 24) | (key[1] << 16) | (key[2] << 8) | key[3], //
      (key[4] << 24) | (key[5] << 16) | (key[6] << 8) | key[7],
      (key[8] << 24) | (key[9] << 16) | (key[10] << 8) | key[11],
      (key[12] << 24) | (key[13] << 16) | (key[14] << 8) | key[15],
    ];
    final k = <int>[mk[0] ^ _kFk[0], mk[1] ^ _kFk[1], mk[2] ^ _kFk[2], mk[3] ^ _kFk[3]];
    final rks = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      final rk = k[i] ^ _tKey(k[i + 1] ^ k[i + 2] ^ k[i + 3] ^ _kCk[i]);
      rks[i] = rk;
      k.add(rk);
    }
    return rks;
  }

  Uint8List _runBlock(List<int> block, {required bool decrypt}) {
    final x = <int>[
      (block[0] << 24) | (block[1] << 16) | (block[2] << 8) | block[3], //
      (block[4] << 24) | (block[5] << 16) | (block[6] << 8) | block[7],
      (block[8] << 24) | (block[9] << 16) | (block[10] << 8) | block[11],
      (block[12] << 24) | (block[13] << 16) | (block[14] << 8) | block[15],
    ];
    for (var i = 0; i < 32; i++) {
      final rk = decrypt ? _roundKeys[31 - i] : _roundKeys[i];
      x.add(x[i] ^ _tEncrypt(x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ rk));
    }
    // 反序变换 R
    final out = Uint8List(16);
    final y0 = x[35], y1 = x[34], y2 = x[33], y3 = x[32];
    out[0] = (y0 >>> 24) & 0xff;
    out[1] = (y0 >>> 16) & 0xff;
    out[2] = (y0 >>> 8) & 0xff;
    out[3] = y0 & 0xff;
    out[4] = (y1 >>> 24) & 0xff;
    out[5] = (y1 >>> 16) & 0xff;
    out[6] = (y1 >>> 8) & 0xff;
    out[7] = y1 & 0xff;
    out[8] = (y2 >>> 24) & 0xff;
    out[9] = (y2 >>> 16) & 0xff;
    out[10] = (y2 >>> 8) & 0xff;
    out[11] = y2 & 0xff;
    out[12] = (y3 >>> 24) & 0xff;
    out[13] = (y3 >>> 16) & 0xff;
    out[14] = (y3 >>> 8) & 0xff;
    out[15] = y3 & 0xff;
    return out;
  }

  /// 加密单个 16 字节块
  Uint8List encryptBlock(List<int> block) {
    if (block.length != 16) throw ArgumentError('SM4 block must be 16 bytes');
    return _runBlock(block, decrypt: false);
  }

  /// 解密单个 16 字节块
  Uint8List decryptBlock(List<int> block) {
    if (block.length != 16) throw ArgumentError('SM4 block must be 16 bytes');
    return _runBlock(block, decrypt: true);
  }
}

/// SM4 工作模式
enum Sm4Mode { ecb, cbc }

/// 面向字节的 SM4 加解密封装：PKCS#7 填充 + ECB/CBC。
/// 证件等敏感 JSON 的加密入口（密钥来自 KeyService，仅存于安全存储）。
class Sm4Cipher {
  Sm4Cipher(this._engine, {this.mode = Sm4Mode.cbc, Uint8List? iv})
      : _iv = iv ?? _randomIv() {
    if (_iv.length != 16) throw ArgumentError('SM4 IV must be 16 bytes');
  }

  final Sm4Engine _engine;
  final Sm4Mode mode;
  final Uint8List _iv;

  static Uint8List _randomIv() {
    final rnd = math.Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static Uint8List _pad(List<int> data) {
    final padLen = 16 - (data.length % 16);
    return Uint8List.fromList([...data, ...List<int>.filled(padLen, padLen)]);
  }

  static Uint8List _unpad(List<int> data) {
    if (data.isEmpty || data.length % 16 != 0) {
      throw const FormatException('SM4 invalid ciphertext length');
    }
    final padLen = data.last;
    if (padLen < 1 || padLen > 16) {
      throw const FormatException('SM4 invalid PKCS7 padding');
    }
    for (var i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw const FormatException('SM4 invalid PKCS7 padding bytes');
      }
    }
    return Uint8List.sublistView(data as Uint8List, 0, data.length - padLen);
  }

  /// 加密任意字节。CBC 模式输出 = IV(16B) + 密文（IV 随密文走）；ECB 输出纯密文。
  Uint8List encrypt(List<int> data) {
    final padded = _pad(data);
    if (mode == Sm4Mode.ecb) {
      final out = Uint8List(padded.length);
      for (var i = 0; i < padded.length; i += 16) {
        final c = _engine.encryptBlock(Uint8List.sublistView(padded, i, i + 16));
        out.setRange(i, i + 16, c);
      }
      return out;
    }
    final out = Uint8List(16 + padded.length);
    out.setRange(0, 16, _iv);
    var prev = _iv;
    for (var i = 0; i < padded.length; i += 16) {
      final block = Uint8List(16);
      for (var j = 0; j < 16; j++) {
        block[j] = padded[i + j] ^ prev[j];
      }
      final c = _engine.encryptBlock(block);
      out.setRange(16 + i, 16 + i + 16, c);
      prev = c;
    }
    return out;
  }

  /// 解密 [encrypt] 的输出。
  Uint8List decrypt(List<int> data) {
    if (mode == Sm4Mode.ecb) {
      if (data.length % 16 != 0) {
        throw const FormatException('SM4 invalid ciphertext length');
      }
      final out = Uint8List(data.length);
      for (var i = 0; i < data.length; i += 16) {
        final p = _engine.decryptBlock(Uint8List.sublistView(Uint8List.fromList(data), i, i + 16));
        out.setRange(i, i + 16, p);
      }
      return _unpad(out);
    }
    if (data.length < 32 || (data.length - 16) % 16 != 0) {
      throw const FormatException('SM4 invalid ciphertext length');
    }
    final iv = Uint8List.sublistView(Uint8List.fromList(data), 0, 16);
    final body = Uint8List.sublistView(Uint8List.fromList(data), 16);
    final out = Uint8List(body.length);
    var prev = iv;
    for (var i = 0; i < body.length; i += 16) {
      final c = Uint8List.sublistView(body, i, i + 16);
      final p = _engine.decryptBlock(c);
      for (var j = 0; j < 16; j++) {
        out[i + j] = p[j] ^ prev[j];
      }
      prev = c;
    }
    return _unpad(out);
  }

  // ---------- 字符串便捷方法（证件 JSON 加密主入口） ----------

  String encryptStringToBase64(String plain) => base64Encode(encrypt(utf8.encode(plain)));

  String decryptStringFromBase64(String b64) => utf8.decode(decrypt(base64Decode(b64)));

  static Uint8List hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw const FormatException('hex length must be even');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// 便捷入口：以 hex 密钥构造
Sm4Cipher sm4CipherFromHexKey(String hexKey, {Sm4Mode mode = Sm4Mode.cbc, Uint8List? iv}) {
  return Sm4Cipher(Sm4Engine(Sm4Cipher.hexToBytes(hexKey)), mode: mode, iv: iv);
}
