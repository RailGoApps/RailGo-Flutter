// lib/features/certificate/certificate_types.dart
//
// 证件类型辅助层：可用性分级、常用子集、旧数据兼容、号码/有效期规则。
// 目录本体（12306 两字母码全量表）见 certificate_catalog.dart（生成文件）。
library;

import 'certificate_catalog.dart';

/// 证件可用性分级
enum CertUsage {
  /// 常用证件：实体证件，可反复用于实名购票
  regular,

  /// 临时证明：短期有效（如乘车当日的临时身份证明）
  temporary,

  /// 一次性证明：用后即失效（救助证/刑满释放证明等）
  oneTime,

  /// 非证件：仅为购票处理规则（免票/无证/补票前缀），不进证件库
  nonDocument,
}

String certUsageLabel(CertUsage u) => switch (u) {
      CertUsage.regular => '常用证件',
      CertUsage.temporary => '临时证明',
      CertUsage.oneTime => '一次性证明',
      CertUsage.nonDocument => '非证件规则',
    };

/// 各类型分级（判断依据：12306 实名购票口径 + 证件物理属性）
const Map<String, CertUsage> kCertUsage = {
  'ED': CertUsage.regular,
  'WJ': CertUsage.regular,
  'JG': CertUsage.regular,
  'YW': CertUsage.regular,
  'SG': CertUsage.regular,
  'WY': CertUsage.regular,
  'WG': CertUsage.regular,
  'JS': CertUsage.regular,
  'WS': CertUsage.regular,
  'WH': CertUsage.regular,
  'HZ': CertUsage.regular,
  'GN': CertUsage.regular,
  'LX': CertUsage.regular,
  'NG': CertUsage.regular,
  'NT': CertUsage.regular,
  'TN': CertUsage.regular,
  'WL': CertUsage.regular,
  'WR': CertUsage.regular,
  'RJ': CertUsage.regular,
  'GJ': CertUsage.regular,
  'TJ': CertUsage.regular,
  'HY': CertUsage.regular,
  'HK': CertUsage.regular,
  'CS': CertUsage.regular,
  'QT': CertUsage.regular,
  'LS': CertUsage.temporary,
  'BS': CertUsage.temporary,
  'SF': CertUsage.oneTime,
  'JJ': CertUsage.oneTime,
  'DL': CertUsage.oneTime,
  'BP(证件号码前添加)': CertUsage.nonDocument,
  'WZ': CertUsage.nonDocument,
  'MP': CertUsage.nonDocument,
};

CertUsage certUsage(String code) => kCertUsage[code] ?? CertUsage.regular;

/// 可入库存放（排除"非证件"类：免票/无证/补票前缀）
bool certStorable(String code) => certUsage(code) != CertUsage.nonDocument;

/// UI 默认展示的常用类型（完整目录在"全部类型"里展开）
const List<String> kPrimaryCertCodes = [
  'ED',
  'HZ',
  'GN',
  'NG',
  'NT',
  'TN',
  'WL',
  'GJ',
  'TJ',
  'WH',
  'LX',
  'HY',
  'HK',
  'CS',
];

/// 旧版存储（枚举名）→ 12306 两字母码
const Map<String, String> kLegacyCertTypeName = {
  'residentId': 'ED',
  'passport': 'HZ',
  'hkmTravelPermit': 'NG',
  'twTravelPermit': 'TN',
  'other': 'QT',
};

/// 兼容旧枚举名/小写码/未知码（未知一律落 QT，不丢数据）
String normalizeTypeCode(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return 'QT';
  final legacy = kLegacyCertTypeName[s];
  if (legacy != null) return legacy;
  final upper = s.toUpperCase();
  return kCertCatalog.containsKey(upper) ? upper : 'QT';
}

String certDisplayName(String code) =>
    kCertCatalog[code]?.name ?? '未知类型($code)';

/// 卡片短名（票面名优先：二代居民身份证 → 居民身份证）
String certShortName(String code) {
  final spec = kCertCatalog[code];
  if (spec == null) return '未知类型($code)';
  return spec.printName ?? spec.name;
}

String? certRemark(String code) => kCertCatalog[code]?.remark;

/// 号码内嵌出生日期（可自动识读）
bool certNumberEncodesBirth(String code) =>
    const {'ED', 'GJ', 'TJ', 'WL'}.contains(code);

/// 号码录入提示
String certNumberHint(String code) => switch (code) {
      'ED' => '18 位（末位可为 X）；15 位旧证同样支持识读',
      'GJ' || 'TJ' => '18 位居住证号码，内嵌出生日期',
      'WL' => '15 位永居证号码，内嵌出生日期',
      'HZ' => 'E+8 位数字；支持 MRZ 机读区识读',
      'WH' => '外国护照号；支持 MRZ 机读区识读',
      'GN' => 'H/M + 8 位或 10 位号码',
      'NG' => 'C + 8 位号码',
      'TN' => '8 位号码',
      _ => '',
    };

/// 中国籍判定（缺省视为中国籍——BS 等类型默认面向国内用户）
bool isChineseNationality(String? nationalityCode) =>
    nationalityCode == null || nationalityCode == 'CHN';

/// 使用限制提示（null = 无特殊限制）
/// - CS 出生医学证明：仅限 6 周岁以下
/// - BS 护照报失证明：中国籍无天数限制；非中国籍 30 天
String? certLimitationHint(String code, {String? nationalityCode}) {
  switch (code) {
    case 'CS':
      return '仅限 6 周岁以下使用';
    case 'BS':
      return isChineseNationality(nationalityCode)
          ? '中国籍：无使用天数限制'
          : '非中国籍：有效期 30 天';
  }
  return certRemark(code);
}

/// 有效期上限（天）；null = 无上限。
/// BS：非中国籍 30 天；中国籍不限制。
int? certMaxValidityDays(String code, {String? nationalityCode}) {
  if (code == 'BS' && !isChineseNationality(nationalityCode)) return 30;
  return null;
}

/// 年龄上限（周岁）；CS 出生医学证明 = 6
int? certMaxAgeYears(String code) => code == 'CS' ? 6 : null;

// ─────────────── 到期时间策略 ───────────────

/// 到期时间填写策略
enum CertExpiryPolicy {
  /// 可不填（长期证件，如身份证/户口簿）
  optional,

  /// 建议填写（有固定有效期的本式/卡式证件）
  recommended,

  /// 必填（短期/临时证件，不填无法判断可用性）
  required,
}

String certExpiryPolicyLabel(CertExpiryPolicy p) => switch (p) {
      CertExpiryPolicy.optional => '可不填',
      CertExpiryPolicy.recommended => '建议填写',
      CertExpiryPolicy.required => '必填',
    };

/// 各证件类型的到期时间策略：
/// - LS 临时身份证明 / WR 外国人出入境证：短期证件 → 必填
/// - BS：中国籍不限天数 → 可不填；非中国籍 30 天 → 必填
/// - 护照/通行证/居住证/海员证等固定有效期证件 → 建议填写
/// - 身份证/户口簿（多为长期）→ 可不填
CertExpiryPolicy certExpiryPolicy(String code, {String? nationalityCode}) {
  switch (code) {
    case 'LS':
    case 'WR':
      return CertExpiryPolicy.required;
    case 'BS':
      return isChineseNationality(nationalityCode)
          ? CertExpiryPolicy.optional
          : CertExpiryPolicy.required;
    case 'HZ':
    case 'WH':
    case 'GN':
    case 'NG':
    case 'NT':
    case 'TN':
    case 'LX':
    case 'HY':
    case 'WL':
    case 'GJ':
    case 'TJ':
      return CertExpiryPolicy.recommended;
    default:
      return CertExpiryPolicy.optional;
  }
}

/// 到期状态
enum CertExpiryStatus { unknown, valid, expiringSoon, expired }

class CertExpiryInfo {
  const CertExpiryInfo({
    required this.status,
    this.daysRemaining,
  });

  final CertExpiryStatus status;

  /// 距到期天数（0=当天到期；负数=已过期天数；unknown 时为 null）
  final int? daysRemaining;

  static const unknownInfo = CertExpiryInfo(status: CertExpiryStatus.unknown);
}

/// 到期状态计算（按日历日零点对零点：当天到期算 expiringSoon，昨日即 expired；
/// warningDays 内均提醒）
CertExpiryInfo certExpiryInfo(
  String? expiryYmd, {
  DateTime? now,
  int warningDays = 30,
}) {
  if (expiryYmd == null || expiryYmd.length != 8) {
    return CertExpiryInfo.unknownInfo;
  }
  final y = int.tryParse(expiryYmd.substring(0, 4));
  final m = int.tryParse(expiryYmd.substring(4, 6));
  final d = int.tryParse(expiryYmd.substring(6, 8));
  if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1) {
    return CertExpiryInfo.unknownInfo;
  }
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final days = DateTime(y, m, d).difference(today).inDays;
  if (days < 0) {
    return CertExpiryInfo(
      status: CertExpiryStatus.expired,
      daysRemaining: days,
    );
  }
  return CertExpiryInfo(
    status: days <= warningDays
        ? CertExpiryStatus.expiringSoon
        : CertExpiryStatus.valid,
    daysRemaining: days,
  );
}
