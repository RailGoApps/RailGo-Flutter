// Zero-Trust 安全姿态：分级与整改建议
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/security/security_posture.dart';

void main() {
  test('全满足 → 硬件级加固，且无整改建议', () {
    const facts = SecurityPostureFacts(
      secureStorageOk: true,
      biometricKinds: ['面容', '指纹'],
      pinConfigured: true,
      sessionRelockEnabled: true,
    );
    expect(assessSecurityPosture(facts), SecurityPostureLevel.hardened);
    expect(securityPostureAdvice(facts), isEmpty);
  });

  test('安全存储自检失败 → 一票降级', () {
    const facts = SecurityPostureFacts(
      secureStorageOk: false,
      biometricKinds: ['指纹'],
      pinConfigured: true,
      sessionRelockEnabled: true,
    );
    expect(assessSecurityPosture(facts), SecurityPostureLevel.degraded);
    expect(securityPostureAdvice(facts).first, contains('硬件安全存储'));
  });

  test('无生物识别且无 PIN → 降级（无可用门禁）', () {
    const facts = SecurityPostureFacts(
      secureStorageOk: true,
      biometricKinds: [],
      pinConfigured: false,
      sessionRelockEnabled: true,
    );
    expect(assessSecurityPosture(facts), SecurityPostureLevel.degraded);
    expect(securityPostureAdvice(facts).where((a) => a.contains('PIN')),
        isNotEmpty);
  });

  test('设备凭据可替代生物识别避免降级，但缺 PIN/会话边界 → 标准', () {
    const facts = SecurityPostureFacts(
      secureStorageOk: true,
      biometricKinds: [],
      pinConfigured: false,
      sessionRelockEnabled: true,
      deviceCredentialLikelySet: true,
    );
    expect(assessSecurityPosture(facts), SecurityPostureLevel.standard);

    const noRelock = SecurityPostureFacts(
      secureStorageOk: true,
      biometricKinds: ['面容'],
      pinConfigured: true,
      sessionRelockEnabled: false,
    );
    expect(assessSecurityPosture(noRelock), SecurityPostureLevel.standard);
    expect(securityPostureAdvice(noRelock).any((a) => a.contains('自动过期')),
        isTrue);
  });

  test('硬件加密说明常量非空（文档性回归锚点）', () {
    expect(kHardwareCryptoPostureNotes, isNotEmpty);
    expect(kHardwareCryptoPostureNotes.join(), contains('Keystore'));
    expect(kHardwareCryptoPostureNotes.join(), contains('Keychain'));
  });
}
