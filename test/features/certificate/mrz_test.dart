// MRZ（ICAO 9303）识读：TD1/TD2/TD3 全字段 + 校验位 + 归一化
// 向量手工构造，校验位按 7-3-1 加权 mod 10 计算验证。
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/certificate/id_number.dart';
import 'package:railgo/features/certificate/mrz.dart';

void main() {
  final now = DateTime(2026, 9, 24);

  // 护照 TD3（2×44）：E12345678 / CHN / 1990-03-07 / M / 2026-09-30
  final td3 = [
    'P<CHNZHANG<<SAN${'<' * 29}',
    'E123456782CHN9003071M2609304${'<' * 14}07',
  ].join('\n');

  // ID 卡 TD1（3×30）：同主体
  final td1 = [
    'I<CHNE123456782${'<' * 15}',
    '9003071M2609304CHN${'<' * 11}7',
    'ZHANG<<SAN${'<' * 20}',
  ].join('\n');

  // TD2（2×36）：英国签发（非 CHN ID → QT）
  final td2 = [
    'I<GBRZHANG<<SAN${'<' * 21}',
    'E123456782GBR9003071M2609304${'<' * 7}7',
  ].join('\n');

  test('TD3 护照：全字段解析 + 全部校验位通过 + 映射 HZ', () {
    final r = parseMrz(td3, now: now);
    expect(r.format, MrzFormat.td3);
    expect(r.docType, 'P');
    expect(r.issuerCode, 'CHN');
    expect(r.fullName, 'ZHANG SAN');
    expect(r.documentNumber, 'E12345678');
    expect(r.nationalityCode, 'CHN');
    expect(r.nationalityName, contains('中国'));
    expect(r.birthDate, '19900307'); // 90 → 2090 未来 → 1990
    expect(r.sex, CertGender.male); // M
    expect(r.expiryDate, '20260930');
    expect(r.docNumberCheckOk, isTrue);
    expect(r.birthCheckOk, isTrue);
    expect(r.expiryCheckOk, isTrue);
    expect(r.personalNumberCheckOk, isTrue);
    expect(r.compositeCheckOk, isTrue);
    expect(r.allChecksOk, isTrue);
    expect(r.certTypeCode, 'HZ');
  });

  test('TD1 ID 卡：CHN 签发 → WL 永居证', () {
    final r = parseMrz(td1, now: now);
    expect(r.format, MrzFormat.td1);
    expect(r.fullName, 'ZHANG SAN');
    expect(r.birthDate, '19900307');
    expect(r.expiryDate, '20260930');
    expect(r.allChecksOk, isTrue);
    expect(r.certTypeCode, 'WL');
  });

  test('TD2：非 CHN 签发 ID → QT，国籍名映射', () {
    final r = parseMrz(td2, now: now);
    expect(r.format, MrzFormat.td2);
    expect(r.issuerCode, 'GBR');
    expect(r.nationalityName, contains('United Kingdom'));
    expect(r.allChecksOk, isTrue);
    expect(r.certTypeCode, 'QT');
  });

  test('综合校验位破坏被识出', () {
    final broken = td3.replaceRange(
      td3.length - 1,
      td3.length,
      '8',
    );
    final r = parseMrz(broken, now: now);
    expect(r.compositeCheckOk, isFalse);
    expect(r.allChecksOk, isFalse);
  });

  test('归一化：小写/空格填充/单行连打 88 位', () {
    final single = td3.toLowerCase().replaceAll('\n', ' ');
    final r = parseMrz(single, now: now);
    expect(r.format, MrzFormat.td3);
    expect(r.documentNumber, 'E12345678');
    expect(r.allChecksOk, isTrue);
  });

  test('格式错误 → FormatException', () {
    expect(() => parseMrz('ABC'), throwsA(isA<FormatException>()));
    expect(() => parseMrz(''), throwsA(isA<FormatException>()));
  });
}
