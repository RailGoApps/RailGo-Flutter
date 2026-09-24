// lib/features/certificate/id_number.dart
//
// 证件号码识读：从号码本身提取出生日期 / 性别 / 校验状态（纯函数，可单测）。
// 覆盖：二代居民身份证(18)、一代旧证(15)、港澳/台湾居民居住证(18，
// 与身份证同构 GB 11643)、外国人永久居留身份证(15)。
library;

enum CertGender { male, female, unknown }

String certGenderLabel(CertGender g) => switch (g) {
      CertGender.male => '男',
      CertGender.female => '女',
      CertGender.unknown => '未知',
    };

class IdNumberInsight {
  const IdNumberInsight({
    this.birthDate,
    this.gender = CertGender.unknown,
    this.checksumOk,
    this.regionCode,
    this.warning,
  });

  /// yyyymmdd
  final String? birthDate;
  final CertGender gender;

  /// null = 该类型号码无校验位（旧证/永居证）
  final bool? checksumOk;

  /// 省级行政区划前两位（如 11=北京市）
  final String? regionCode;
  final String? warning;

  bool get hasData =>
      birthDate != null ||
      gender != CertGender.unknown ||
      checksumOk != null ||
      regionCode != null;

  String? get formattedBirth {
    final b = birthDate;
    if (b == null || b.length != 8) return null;
    return '${b.substring(0, 4)}-${b.substring(4, 6)}-${b.substring(6, 8)}';
  }
}

const Map<String, String> kRegionNames = {
  '11': '北京市',
  '12': '天津市',
  '13': '河北省',
  '14': '山西省',
  '15': '内蒙古自治区',
  '21': '辽宁省',
  '22': '吉林省',
  '23': '黑龙江省',
  '31': '上海市',
  '32': '江苏省',
  '33': '浙江省',
  '34': '安徽省',
  '35': '福建省',
  '36': '江西省',
  '37': '山东省',
  '41': '河南省',
  '42': '湖北省',
  '43': '湖南省',
  '44': '广东省',
  '45': '广西壮族自治区',
  '46': '海南省',
  '50': '重庆市',
  '51': '四川省',
  '52': '贵州省',
  '53': '云南省',
  '54': '西藏自治区',
  '61': '陕西省',
  '62': '甘肃省',
  '63': '青海省',
  '64': '宁夏回族自治区',
  '65': '新疆维吾尔自治区',
  '71': '台湾省',
  '81': '香港特别行政区',
  '82': '澳门特别行政区',
};

/// 周岁（生日未过减一）；无效返回 null
int? certAgeAt(String? birthYmd, DateTime now) {
  if (birthYmd == null || birthYmd.length != 8) return null;
  final y = int.tryParse(birthYmd.substring(0, 4));
  final m = int.tryParse(birthYmd.substring(4, 6));
  final d = int.tryParse(birthYmd.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  var age = now.year - y;
  if (now.month < m || (now.month == m && now.day < d)) age--;
  return age < 0 ? null : age;
}

bool _validYmd(String s) {
  if (s.length != 8) return false;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return false;
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  final dt = DateTime(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d;
}

/// GB 11643 / ISO 7064 MOD 11-2 校验位
const List<int> _kIdWeights = [
  7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2,
];
const String _kCheckChars = '10X98765432';

/// 分析证件号码：出生日期/性别/校验位/省级行政区划。
/// 未知类型返回空 Insight（UI 不显示任何推断）。
IdNumberInsight analyzeCertNumber(String typeCode, String raw) {
  final n = raw.trim().replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  switch (typeCode) {
    case 'ED':
    case 'GJ':
    case 'TJ':
      if (RegExp(r'^\d{17}[\dX]$').hasMatch(n)) return _resident18(n);
      if (typeCode == 'ED' && RegExp(r'^\d{15}$').hasMatch(n)) {
        return _resident15(n);
      }
      return const IdNumberInsight(
        warning: '号码位数不符（应为 18 位，旧证 15 位）',
      );
    case 'WL':
      if (RegExp(r'^\d{15}$').hasMatch(n)) return _frPermanent15(n);
      return const IdNumberInsight(warning: '号码位数不符（应为 15 位）');
    default:
      return const IdNumberInsight();
  }
}

IdNumberInsight _resident18(String n) {
  final birth = n.substring(6, 14);
  final warnings = <String>[];
  final birthOk = _validYmd(birth);
  if (!birthOk) warnings.add('出生日期段非法');

  final seqDigit = int.tryParse(n.substring(16, 17));
  final gender = seqDigit == null
      ? CertGender.unknown
      : (seqDigit % 2 == 1 ? CertGender.male : CertGender.female);

  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += (n.codeUnitAt(i) - 0x30) * _kIdWeights[i];
  }
  final checksumOk = _kCheckChars[sum % 11] == n.substring(17);
  if (!checksumOk) warnings.add('校验位不符，请核对号码');

  final region = n.substring(0, 2);
  return IdNumberInsight(
    birthDate: birthOk ? birth : null,
    gender: gender,
    checksumOk: checksumOk,
    regionCode: kRegionNames.containsKey(region) ? region : null,
    warning: warnings.isEmpty ? null : warnings.join('；'),
  );
}

IdNumberInsight _resident15(String n) {
  final birth = '19${n.substring(6, 12)}';
  final birthOk = _validYmd(birth);
  final seqDigit = int.tryParse(n.substring(14, 15));
  return IdNumberInsight(
    birthDate: birthOk ? birth : null,
    gender: seqDigit == null
        ? CertGender.unknown
        : (seqDigit % 2 == 1 ? CertGender.male : CertGender.female),
    regionCode: kRegionNames.containsKey(n.substring(0, 2))
        ? n.substring(0, 2)
        : null,
    warning: birthOk ? null : '出生日期段非法（旧 15 位证）',
  );
}

/// 外国人永久居留身份证：3 位受理机关 + 8 位出生日期 + 4 位顺序。
/// 顺序码性别规则与身份证不同（不做推断）；无校验位。
IdNumberInsight _frPermanent15(String n) {
  final birth = n.substring(3, 11);
  final ok = _validYmd(birth);
  return IdNumberInsight(
    birthDate: ok ? birth : null,
    warning: ok ? null : '出生日期段非法（永居证）',
  );
}
