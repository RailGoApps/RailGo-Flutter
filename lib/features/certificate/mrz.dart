// lib/features/certificate/mrz.dart
//
// ICAO Doc 9303 机读区（MRZ）识读（纯函数，可单测）：
//   TD1 = 3 行 × 30 位（ID 卡）
//   TD2 = 2 行 × 36 位
//   TD3 = 2 行 × 44 位（护照本）
// 7-3-1 加权校验位逐项验证；国别码经 certificate_catalog 映射为可读名称。
library;

import 'certificate_catalog.dart';
import 'id_number.dart';

enum MrzFormat { td1, td2, td3 }

String mrzFormatLabel(MrzFormat f) => switch (f) {
      MrzFormat.td1 => 'TD1（ID 卡 3×30）',
      MrzFormat.td2 => 'TD2（2×36）',
      MrzFormat.td3 => 'TD3（护照本 2×44）',
    };

class MrzResult {
  const MrzResult({
    required this.format,
    required this.docType,
    required this.issuerCode,
    required this.surname,
    required this.givenNames,
    required this.documentNumber,
    required this.nationalityCode,
    required this.birthDate,
    required this.sex,
    required this.expiryDate,
    required this.docNumberCheckOk,
    required this.birthCheckOk,
    required this.expiryCheckOk,
    required this.compositeCheckOk,
    required this.personalNumberCheckOk,
    required this.warnings,
  });

  final MrzFormat format;

  /// 证件类别字母（P=护照 I=ID卡 V=签证 AC=船员证…，含填充符）
  final String docType;
  final String issuerCode;
  final String surname;
  final String givenNames;
  final String documentNumber;
  final String nationalityCode;

  /// yyyymmdd（世纪由当前时间推断：未来即 19xx）
  final String birthDate;
  final CertGender sex;

  /// yyyymmdd
  final String expiryDate;

  final bool docNumberCheckOk;
  final bool birthCheckOk;
  final bool expiryCheckOk;
  final bool compositeCheckOk;

  /// 仅 TD3（护照）个人号有独立校验位
  final bool personalNumberCheckOk;
  final List<String> warnings;

  String get fullName =>
      givenNames.isEmpty ? surname : '$surname $givenNames';

  String get issuerName => kIso3Names[issuerCode] ?? issuerCode;

  String get nationalityName =>
      kIso3Names[nationalityCode] ?? nationalityCode;

  bool get allChecksOk =>
      docNumberCheckOk &&
      birthCheckOk &&
      expiryCheckOk &&
      compositeCheckOk &&
      personalNumberCheckOk;

  /// 映射到 12306 证件代码：
  /// TD3 护照：中国签发→HZ 中国护照；否则→WH 外国人护照。
  /// ID 类：中国签发→WL 外国人永久居留身份证（唯一带 MRZ 的中国 ID 卡）；否则→QT。
  String get certTypeCode {
    final t = docType.substring(0, 1);
    if (format == MrzFormat.td3 && t == 'P') {
      return issuerCode == 'CHN' ? 'HZ' : 'WH';
    }
    if (t == 'I') return issuerCode == 'CHN' ? 'WL' : 'QT';
    return 'QT';
  }
}

/// 解析 MRZ 文本（支持换行分隔、扫描枪单行连打、空格填充、小写）。
/// 格式不符抛 [FormatException]。
MrzResult parseMrz(String raw, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final lines = _normalizeLines(raw);
  if (lines.isEmpty) {
    throw const FormatException('机读区内容为空');
  }
  if (lines.length == 3 && lines.every((l) => l.length == 30)) {
    return _parseTd1(lines, at);
  }
  if (lines.length == 2 && lines.every((l) => l.length == 44)) {
    return _parseTd3(lines, at);
  }
  if (lines.length == 2 && lines.every((l) => l.length == 36)) {
    return _parseTd2(lines, at);
  }
  throw FormatException(
      '机读区应为 3×30（TD1）、2×36（TD2）或 2×44（TD3），'
      '当前 ${lines.length} 行：${lines.map((l) => l.length).join('/')}');
}

List<String> _normalizeLines(String raw) {
  var out = <String>[];
  for (final line in raw.toUpperCase().split(RegExp(r'[\r\n]+'))) {
    final sb = StringBuffer();
    for (final cu in line.codeUnits) {
      if (cu >= 0x30 && cu <= 0x39) {
        sb.writeCharCode(cu);
      } else if (cu >= 0x41 && cu <= 0x5A) {
        sb.writeCharCode(cu);
      } else if (cu == 0x3C || cu == 0x20) {
        sb.write('<'); // 空格视为填充符
      }
    }
    if (sb.isNotEmpty) out.add(sb.toString());
  }
  // 扫描枪常把多行连打为一行：按标准宽度切分
  if (out.length == 1) {
    final s = out.first;
    if (s.length == 88) {
      out = [s.substring(0, 44), s.substring(44)];
    } else if (s.length == 72) {
      out = [s.substring(0, 36), s.substring(36)];
    } else if (s.length == 90) {
      out = [s.substring(0, 30), s.substring(30, 60), s.substring(60)];
    }
  }
  return out;
}

int _charValue(String ch) {
  final c = ch.codeUnitAt(0);
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x5A) return c - 0x41 + 10;
  return 0; // '<' 及一切填充
}

int _checkDigit(String field) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    sum += _charValue(field[i]) * weights[i % 3];
  }
  return sum % 10;
}

bool _check(String field, String digit) =>
    _checkDigit(field) == _charValue(digit);

String _stripFill(String s) => s.replaceAll('<', '');

String _fillToSpace(String s) =>
    s.replaceAll('<', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

(String, String) _parseName(String field) {
  final parts = field.split('<<');
  final surname = _fillToSpace(parts.first);
  final given =
      parts.skip(1).map(_fillToSpace).where((s) => s.isNotEmpty).join(' ');
  return (surname, given);
}

CertGender _parseSex(String ch) {
  if (ch == 'M') return CertGender.male;
  if (ch == 'F') return CertGender.female;
  return CertGender.unknown;
}

/// 出生日期世纪推断：20xx 若未超当前年份，否则 19xx（百岁人瑞也成立）
String _expandBirth(String yymmdd, DateTime now) {
  final yy = int.parse(yymmdd.substring(0, 2));
  final y2k = 2000 + yy;
  final year = y2k > now.year ? 1900 + yy : y2k;
  return '$year${yymmdd.substring(2)}';
}

String _expandExpiry(String yymmdd) => '20$yymmdd';

MrzResult _parseTd1(List<String> l, DateTime now) {
  final l1 = l[0], l2 = l[1], l3 = l[2];
  final docType = _stripFill(l1.substring(0, 2));
  final issuer = _stripFill(l1.substring(2, 5));
  final docNum = _stripFill(l1.substring(5, 14));
  final dob = _expandBirth(l2.substring(0, 6), now);
  final sex = _parseSex(l2.substring(7, 8));
  final exp = _expandExpiry(l2.substring(8, 14));
  final nat = _stripFill(l2.substring(15, 18));
  final (surname, given) = _parseName(l3);
  final warnings = <String>[];
  if (l1.substring(5, 14).contains('<')) {
    warnings.add('证件号中含填充符');
  }
  return MrzResult(
    format: MrzFormat.td1,
    docType: docType,
    issuerCode: issuer,
    surname: surname,
    givenNames: given,
    documentNumber: docNum,
    nationalityCode: nat,
    birthDate: dob,
    sex: sex,
    expiryDate: exp,
    docNumberCheckOk: _check(l1.substring(5, 14), l1.substring(14, 15)),
    birthCheckOk: _check(l2.substring(0, 6), l2.substring(6, 7)),
    expiryCheckOk: _check(l2.substring(8, 14), l2.substring(14, 15)),
    compositeCheckOk: _check(
        l1.substring(5, 30) +
            l2.substring(0, 7) +
            l2.substring(8, 15) +
            l2.substring(18, 29),
        l2.substring(29, 30)),
    personalNumberCheckOk: true, // TD1 无独立个人号校验位
    warnings: warnings,
  );
}

MrzResult _parseTd2(List<String> l, DateTime now) {
  final l1 = l[0], l2 = l[1];
  final docType = _stripFill(l1.substring(0, 2));
  final issuer = _stripFill(l1.substring(2, 5));
  final (surname, given) = _parseName(l1.substring(5, 36));
  final docNum = _stripFill(l2.substring(0, 9));
  final nat = _stripFill(l2.substring(10, 13));
  final dob = _expandBirth(l2.substring(13, 19), now);
  final sex = _parseSex(l2.substring(20, 21));
  final exp = _expandExpiry(l2.substring(21, 27));
  return MrzResult(
    format: MrzFormat.td2,
    docType: docType,
    issuerCode: issuer,
    surname: surname,
    givenNames: given,
    documentNumber: docNum,
    nationalityCode: nat,
    birthDate: dob,
    sex: sex,
    expiryDate: exp,
    docNumberCheckOk: _check(l2.substring(0, 9), l2.substring(9, 10)),
    birthCheckOk: _check(l2.substring(13, 19), l2.substring(19, 20)),
    expiryCheckOk: _check(l2.substring(21, 27), l2.substring(27, 28)),
    compositeCheckOk: _check(
        l2.substring(0, 10) +
            l2.substring(13, 20) +
            l2.substring(21, 28) +
            l2.substring(28, 35),
        l2.substring(35, 36)),
    personalNumberCheckOk: true, // TD2 无独立个人号校验位
    warnings: l2.substring(0, 9).contains('<')
        ? ['证件号中含填充符']
        : const <String>[],
  );
}

MrzResult _parseTd3(List<String> l, DateTime now) {
  final l1 = l[0], l2 = l[1];
  final docType = _stripFill(l1.substring(0, 2));
  final issuer = _stripFill(l1.substring(2, 5));
  final (surname, given) = _parseName(l1.substring(5, 44));
  final docNum = _stripFill(l2.substring(0, 9));
  final nat = _stripFill(l2.substring(10, 13));
  final dob = _expandBirth(l2.substring(13, 19), now);
  final sex = _parseSex(l2.substring(20, 21));
  final exp = _expandExpiry(l2.substring(21, 27));
  return MrzResult(
    format: MrzFormat.td3,
    docType: docType,
    issuerCode: issuer,
    surname: surname,
    givenNames: given,
    documentNumber: docNum,
    nationalityCode: nat,
    birthDate: dob,
    sex: sex,
    expiryDate: exp,
    docNumberCheckOk: _check(l2.substring(0, 9), l2.substring(9, 10)),
    birthCheckOk: _check(l2.substring(13, 19), l2.substring(19, 20)),
    expiryCheckOk: _check(l2.substring(21, 27), l2.substring(27, 28)),
    compositeCheckOk: _check(
        l2.substring(0, 10) +
            l2.substring(13, 20) +
            l2.substring(21, 28) +
            l2.substring(28, 43),
        l2.substring(43, 44)),
    personalNumberCheckOk:
        _check(l2.substring(28, 42), l2.substring(42, 43)),
    warnings: l2.substring(0, 9).contains('<')
        ? ['证件号中含填充符']
        : const <String>[],
  );
}
