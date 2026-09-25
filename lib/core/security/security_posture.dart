// lib/core/security/security_posture.dart
//
// Zero-Trust 安全姿态评估（纯逻辑，可单测）：
//   输入设备事实（安全存储自检 / 生物识别 / PIN / 会话边界），
//   输出分级结论与整改建议，供证件页"通行密钥"面板展示。
//   原则：任何单项缺失都不致命，但姿态分级的语义必须保守——
//   不满足"硬件加密 + 强门禁 + 会话边界"即不得评为 hardened。
library;

enum SecurityPostureLevel { hardened, standard, degraded }

class SecurityPostureFacts {
  const SecurityPostureFacts({
    required this.secureStorageOk,
    required this.biometricKinds,
    required this.pinConfigured,
    required this.sessionRelockEnabled,
    this.deviceCredentialLikelySet = false,
  });

  /// SM4 主密钥安全存储自检通过（Android Keystore / iOS Keychain 可用）
  final bool secureStorageOk;

  /// 已登记的生物识别种类（面容/指纹/虹膜…）
  final List<String> biometricKinds;

  /// 6 位 PIN 回退已设置
  final bool pinConfigured;

  /// 会话授权自动过期（Zero-Trust 会话边界）
  final bool sessionRelockEnabled;

  /// 系统锁屏凭据（PIN/图案/密码）大概率已设置——local_auth 的
  /// biometricOnly=false 语义下可作为设备级强凭据回退
  final bool deviceCredentialLikelySet;

  bool get hasBiometric => biometricKinds.isNotEmpty;
}

const String kPostureHardenedLabel = '硬件级加固';
const String kPostureStandardLabel = '标准防护';
const String kPostureDegradedLabel = '防护降级';

/// 平台硬件加密事实（不可单测的文档性常量；与 key_service.dart 装配一致）
const List<String> kHardwareCryptoPostureNotes = <String>[
  'Android：SM4 主密钥经 Android Keystore 包装存储'
  '（flutter_secure_storage encryptedSharedPreferences）',
  'iOS：SM4 主密钥存于 Keychain（ThisDeviceOnly，首次解锁后可用）',
  'HarmonyOS：经通用 Keystore/安全存储适配（HAP 构建后生效）',
  '密钥仅存在于内存与安全存储，绝不落明文盘（审计红队规则）',
];

SecurityPostureLevel assessSecurityPosture(SecurityPostureFacts f) {
  if (!f.secureStorageOk) return SecurityPostureLevel.degraded;
  final strongGate = f.hasBiometric || f.deviceCredentialLikelySet;
  if (!strongGate && !f.pinConfigured) return SecurityPostureLevel.degraded;
  if (f.hasBiometric && f.pinConfigured && f.sessionRelockEnabled) {
    return SecurityPostureLevel.hardened;
  }
  return SecurityPostureLevel.standard;
}

/// 整改建议（按缺失项输出；hardened 时为空）
List<String> securityPostureAdvice(SecurityPostureFacts f) {
  final out = <String>[];
  if (!f.secureStorageOk) {
    out.add('硬件安全存储不可用：敏感数据将无法可靠加密，'
        '请在系统设置中检查锁屏与凭据后重启应用');
  }
  if (!f.hasBiometric) {
    out.add('未登记生物识别：建议在系统中登记面容/指纹，'
        '作为证件库的强门禁');
  }
  if (!f.pinConfigured) {
    out.add('未设置 PIN 回退：生物识别失败时将无法访问证件库');
  }
  if (!f.sessionRelockEnabled) {
    out.add('会话授权未启用自动过期：建议启用 5 分钟自动上锁'
        '（Zero-Trust 会话边界）');
  }
  return out;
}
