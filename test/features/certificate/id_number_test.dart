// 证件号码识读：身份证/居住证/永居证 → 出生日期、性别、校验位、年龄
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/certificate/id_number.dart';

void main() {
  // 校验位由 GB 11643 ISO 7064 MOD 11-2 计算：本用例号码为手工验证向量
  const valid18 = '110101199003077758';

  test('二代身份证 18 位：出生/性别/校验/行政区划', () {
    final r = analyzeCertNumber('ED', valid18);
    expect(r.birthDate, '19900307');
    expect(r.gender, CertGender.male); // 顺序码末位 5（奇）→ 男
    expect(r.checksumOk, isTrue);
    expect(r.regionCode, '11');
    expect(kRegionNames[r.regionCode], '北京市');
    expect(r.warning, isNull);
    expect(r.formattedBirth, '1990-03-07');
  });

  test('校验位不符被识出（末位改 7）', () {
    final r = analyzeCertNumber('ED', '110101199003077757');
    expect(r.birthDate, '19900307'); // 出生日期段仍有效
    expect(r.checksumOk, isFalse);
    expect(r.warning, contains('校验位'));
  });

  test('末位小写 x 自动归一（真实校验位为 X 的号码）', () {
    // 前 17 位 11010119900307774 的 GB 11643 校验位为 X（加权和 244 → 余 2）
    final r = analyzeCertNumber('ED', '11010119900307774x');
    expect(r.checksumOk, isTrue);
    expect(r.gender, CertGender.female); // 顺序码末位 6（偶）→ 女
  });

  test('一代旧证 15 位：补 19 世纪出生、奇偶性别、无校验位', () {
    final r = analyzeCertNumber('ED', '110101900307775');
    expect(r.birthDate, '19900307');
    expect(r.gender, CertGender.male);
    expect(r.checksumOk, isNull);
    expect(r.regionCode, '11');
  });

  test('港澳/台湾居民居住证与身份证同构识读', () {
    final r = analyzeCertNumber('GJ', valid18);
    expect(r.birthDate, '19900307');
    expect(r.checksumOk, isTrue);
  });

  test('外国人永久居留身份证 15 位：出生在 4-11 位，不推性别', () {
    final r = analyzeCertNumber('WL', '110199003070775');
    expect(r.birthDate, '19900307');
    expect(r.gender, CertGender.unknown);
    expect(r.checksumOk, isNull);
  });

  test('位数不符给出人话告警；未知类型不做任何推断', () {
    expect(analyzeCertNumber('ED', '123').warning, contains('位数'));
    expect(analyzeCertNumber('WL', '123').warning, contains('位数'));
    final none = analyzeCertNumber('HZ', 'E12345678');
    expect(none.hasData, isFalse);
  });

  test('周岁计算：生日未过减一、生日当天不减', () {
    final at = DateTime(2026, 9, 24);
    expect(certAgeAt('19900307', at), 36);
    expect(certAgeAt('19900924', at), 36); // 当天生日
    expect(certAgeAt('19900925', at), 35); // 明天生日，未过
    expect(certAgeAt('bad', at), isNull);
    expect(certAgeAt(null, at), isNull);
  });
}
