# RailGo 铁路行（Flutter 重构版）

> 仓库：https://github.com/RailGoApps/RailGo-Flutter （由 uni-app 版 https://github.com/RailGoApps/RailGo 重构）
> 状态：**Phase 2 架构与代码生成进行中**（工作分支 `flutter-rewrite`）
> 逆向基线：[`docs/BASELINE.md`](docs/BASELINE.md)（45 页路由矩阵 / 15 个 API 端点 / 15 服务源网关体系，全部实证）

**数据来源：RailGo (railgo.dev)** —— 本项目遵守 [api.railgo.dev 使用限制](https://api.railgo.dev/llms.txt)：不得商业用途、不得公开中转、公开服务须显著标注数据来源。

## 技术栈

| 领域 | 方案 | 容灾降级 |
|---|---|---|
| 状态管理 | Riverpod | — |
| 本地数据库 | sqflite | 内存缓存（SQLite 损坏时） |
| 安全存储 | flutter_secure_storage | 应用内 PIN 派生密钥（Keystore/Keychain 损坏时） |
| 加密 | 国密 SM4（pointycastle 纯 Dart） | — |
| 生物识别 | local_auth | 6 位 PIN / 手势密码 |
| 实时活动 | ActivityKit / 前台服务 / 实况窗 | flutter_local_notifications |
| 传感器测速 | sensors_plus 加速度计积分 | 纯时间驱动 UI |
| 文档页 | flutter_markdown | 硬编码兜底文本 |

三端自适应：**iOS (Cupertino)** / **Android (Material 3 Expressive)** / **HarmonyOS NEXT (ArkUI 风格)**。

## 工程结构

```
lib/
├── core/          # crypto(SM4) security(Passkey) storage network l10n utils(Asia/Shanghai)
├── features/      # trip(状态机+接续) station train emu certificate live_push sensor oobe
├── widgets/       # 三端平台自适应组件（含 MD3E 浮动底栏）
└── main.dart
assets/docs/       # about / eula / privacy / permissions (Markdown)
test/              # 行程状态机 / 接续判断 / SM4 最小单元测试（CI 覆盖率门槛 80%）
.github/           # CI: lint → test(coverage) → license-scan → build(android/ios/harmony) → release
```

原 uni-app 源码（`pages/` `components/` `uni_modules/` 等）**就地保留**作为 Phase 4 的 1:1 业务对照参考，勿删。

## 引导开发（本仓库当前不含平台目录，需一次性生成）

```bash
flutter create . --platforms=android,ios --org com.azstudio --project-name railgo
```

生成后需补丁：
- **Android**：`MainActivity` 改继承 `FlutterFragmentActivity`（local_auth 要求）；minSdk 23。
- **iOS**：Info.plist 增加 `NSFaceIDUsageDescription`、定位三项描述（"用于测速功能"）。
- **HarmonyOS**：使用 OpenHarmony Flutter SDK 社区分支 [CPF-Flutter/flutter_flutter `3.22.0-ohos`](https://gitcode.com/CPF-Flutter/flutter_flutter/tree/3.22.0-ohos)（GitCode 托管，支持 `flutter build hap`）。注意其基线为 Flutter 3.22.0 / Dart 3.4，与 Android/iOS 的 3.27.4 双轨并行——本工程已做双版本兼容（Dart 约束 `>=3.4.0`，禁用 3.27-only API）。权限对齐基线 §1（INTERNET / LOCATION×2）。

鸿蒙本地构建（需 DevEco Studio + OpenHarmony SDK）：
```bash
git clone -b 3.22.0-ohos https://gitcode.com/CPF-Flutter/flutter_flutter.git ohos-flutter
export PATH="$PWD/ohos-flutter/bin:$PATH"
flutter doctor && flutter pub get
flutter build hap --release
```

**CI 构建 HAP**：[`.github/workflows/harmony.yml`](.github/workflows/harmony.yml) 三模式——① 预检（未配置 CLI 直链时打印指引）② 云端构建（仓库 Variable/Secret `OHOS_CLI_URL` 指向 `commandline-tools-linux-x64-*.zip` 直链，ubuntu runner 真构建，产物 unsigned HAP）③ 自建 runner（预装工具链，input `runner=harmonyos`）。配置 Secrets `OHOS_P12_B64/OHOS_P12_PASS/OHOS_CER_B64/OHOS_P7B_B64`（AGC 证书 Base64）即可在 CI 内完成签名注入。

## 授权

见 [`LICENSE.md`](LICENSE.md)：基础 ARR；EDU/个人类 AGPL（修改须开源）；商业需书面授权。禁止欧盟用户使用（协议声明，不做技术拦截）。
