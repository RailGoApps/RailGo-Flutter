// 证件类型辅助层：到期策略 / 到期状态 / BS 30 天规则
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/features/certificate/certificate_types.dart';

void main() {
  final now = DateTime(2026, 9, 24, 12);

  String ymd(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  test('到期状态：过期/当天/临期/有效/未知', () {
    expect(certExpiryInfo(null).status, CertExpiryStatus.unknown);
    expect(certExpiryInfo('bad').status, CertExpiryStatus.unknown);
    expect(
        certExpiryInfo('20260923', now: now).status, CertExpiryStatus.expired);
    expect(certExpiryInfo('20260923', now: now).daysRemaining, -1);

    final today = certExpiryInfo('20260924', now: now);
    expect(today.status, CertExpiryStatus.expiringSoon);
    expect(today.daysRemaining, 0);

    final d30 = certExpiryInfo(ymd(DateTime(2026, 10, 24)), now: now);
    expect(d30.status, CertExpiryStatus.expiringSoon);
    expect(d30.daysRemaining, 30);

    final d31 = certExpiryInfo(ymd(DateTime(2026, 10, 25)), now: now);
    expect(d31.status, CertExpiryStatus.valid);
    expect(d31.daysRemaining, 31);
  });

  test('到期填写策略：短期证件必填；BS 按国籍区分', () {
    expect(certExpiryPolicy('LS'), CertExpiryPolicy.required);
    expect(certExpiryPolicy('WR'), CertExpiryPolicy.required);
    expect(certExpiryPolicy('BS', nationalityCode: 'CHN'),
        CertExpiryPolicy.optional);
    expect(certExpiryPolicy('BS', nationalityCode: 'ZZ'),
        CertExpiryPolicy.required);
    expect(certExpiryPolicy('HZ'), CertExpiryPolicy.recommended);
    expect(certExpiryPolicy('GN'), CertExpiryPolicy.recommended);
    expect(certExpiryPolicy('ED'), CertExpiryPolicy.optional);
  });

  test('BS 有效期上限：非中国籍 30 天，中国籍不限制', () {
    expect(certMaxValidityDays('BS', nationalityCode: 'ZZ'), 30);
    expect(certMaxValidityDays('BS', nationalityCode: 'CHN'), isNull);
    expect(certMaxValidityDays('BS'), isNull);
    expect(certMaxValidityDays('HZ'), isNull);
  });

  test('CS 年龄上限与可用性分级', () {
    expect(certMaxAgeYears('CS'), 6);
    expect(certMaxAgeYears('ED'), isNull);
    // 非证件类（免票/无证/补票前缀）不进证件库
    expect(certStorable('MP'), isFalse);
    expect(certStorable('WZ'), isFalse);
    expect(certStorable('BP(证件号码前添加)'), isFalse);
    expect(certUsage('JJ'), CertUsage.oneTime);
    expect(certUsage('LS'), CertUsage.temporary);
    expect(certUsage('ED'), CertUsage.regular);
  });
}
