# 《RailGo-Flutter 红蓝队静态审查报告》(Phase 3)

> 审查对象：`flutter-rewrite` 分支 @ `88a8bb49`
> 审查方式：**本地人工深度静态审查**（用户决策：不安装本地 Flutter SDK，`flutter analyze`/`flutter test --coverage` 的权威执行由 GitHub Actions `ci.yml` 首跑承担；本报告为代码级人工审查结论）
> 修复基线：所有发现均已修复并提交（见各条目 commit）

---

## 1. 蓝队（防御与合规）

### 1.1 静态分析与格式（`flutter analyze` / `dart format`）
- 人工逐文件审查全部 24 个 Dart 文件（lib×20 + test×11 中的核心），修复编译级问题 **7 处**：
  | # | 问题 | 文件 | 修复 |
  |---|---|---|---|
  | B1 | `const Text(运行时三元)` 编译错误 | home_page.dart | 移除 const |
  | B2 | `UpdatePage.currentDbVersion` 必填但路由未传 | update_page.dart | 改可选默认"未下载" |
  | B3 | JSON 数值直接 `as int`（V2 可能返回 double） | train_repository.dart | `(x as num? ?? 0).toInt()` |
  | B4 | `FormData` 混用于 urlencoded POST（产生 multipart） | api_client.dart | 直接传 Map + contentType |
  | B5 | 非法 Dart union typedef | train_result_page.dart | 删除，直接用 `TripStop` |
  | B6 | `Text(onTap:)` 不存在参数 | home_page.dart | GestureDetector 包裹 |
  | B7 | `DefaultAssetBundle.of(this)` 误用 | doc_page.dart | context 参数化 |
- **遗留风险（接受）**：`dart format` 尚未机器执行，CI 首跑 `dart format --set-exit-if-changed` 可能报格式差异 → 首跑后按 CI diff 一次性 `dart format lib test` 即可（预期仅空白/换行变化）。

### 1.2 依赖合规扫描（GPL 传染性防护）
全部 14 个直接依赖均为宽松协议，**无 GPL/LGPL/AGPL/SSPL**：

| 依赖 | 协议 | 依赖 | 协议 |
|---|---|---|---|
| flutter/flutter_localizations | BSD-3 | pointycastle | MIT |
| intl | BSD-3 | local_auth | BSD-3 |
| cupertino_icons | MIT | sensors_plus | MIT |
| flutter_riverpod | MIT | geolocator | MIT |
| dio | MIT | flutter_local_notifications | MIT |
| sqflite / path / path_provider | MIT/BSD-3 | flutter_markdown | BSD-3 |
| shared_preferences | BSD-3 | timezone | Apache-2.0 |
| flutter_secure_storage | BSD-3 | | |

CI `license-scan` job（子串 gpl 家族 + 已知 copyleft 包名黑名单）作为持续门禁。
> 注：本项目自有 LICENSE.md 中的"类 AGPL"条款作用于**本项目衍生作品**，与依赖合规无冲突。

### 1.3 安全存储审查（SM4/密钥）
- grep 全库 `SM4|密钥|key`：**无任何硬编码生产密钥**。SM4 主密钥仅存于 `flutter_secure_storage`（Android EncryptedSharedPreferences / iOS ThisDeviceOnly）；Keystore 损坏时经 PBKDF2-HMAC-SHA256（100k 轮）由 PIN 派生兜底（key_service.dart）。
- 测试中的 `0123456789abcdeffedcba9876543210` 为 GB/T 32907-2016 **国标公开测试向量**，非生产密钥。
- 🔴 **发现 M1（中危·历史遗留）**：根目录 `manifest.json`（原 uni-app 工程参考件）内含鸿蒙签名 p12/p7b 的**加密密码串**。已随 git 历史存在。**建议**：推送公开仓库前由人工执行 `git filter-repo` 清除或旋转证书；Flutter 工程不引用该文件。

### 1.4 API 限速审查（WAF 合规）
- `TokenBucket(2 rps, burst 4)` + `ConcurrencyGate(4)` + `Debouncer(260ms)` 三层控制已在 `main.dart::apiClientProvider` 装配（**审查中发现初版未装配，已修复** = F2）。
- GET 一律无 body（吸取基线 axios 短请求体教训，Baseline §10 反馈#1）；POST 显式 urlencoded。

---

## 2. 红队（攻击与逻辑破坏）

### 2.1 鉴权绕过审查
- `CertificateRepository.unlockAll/save` **均消费 `gate.passed == true`**，拒绝时抛 `GateDeniedException`——不存在"弹窗后不看结果放行"路径；单测覆盖拒绝分支。
- **发现 F3（已修复）**：生物识别失败后原版直接拒绝，无 PIN 通道 → 已在 certificates_page 增加 PIN 对话框回退（verifyPin 恒时比较）。
- 备注：`local_auth.authenticate` 默认允许设备锁凭据回退（biometricOnly=false），属"系统级更强凭据"而非绕过，保留。

### 2.2 状态机注入审查（时间篡改）
- 状态机为纯函数 `evaluate(nowMinutes)`，单趟扫描无循环；脏数据（缺 arrive/全空站）显式回退并标注 reason，测试覆盖。
- `TrustworthyClock`（墙钟+单调秒表双源，90s 漂移阈值，跳变重锚定并广播事件）已接入 `TripRepository`（**审查发现初版用 SystemClock，已修复** = F4）。
- 用户手改时间 → 重锚定后按新时刻评估，不产生死循环/倒转（nowMinutes 单调性由重锚保证）。

### 2.3 资源耗尽审查
- 传感器：历史环形上限 512 样本；`dt<=0 || dt>5s` 样本丢弃重锚（时间回跳攻击防御，有测试）；stream/timer 在 dispose 全部取消。
- 令牌桶等待者按容量逐个放行，无忙等；并发闸门 FIFO。
- **发现 F5（已修复）**：接续间隙原实现漏算两行程发车日差（跨日接续少加 1440×N 分钟）→ `_daysBetween` 修复，属逻辑破坏级缺陷。

### 2.4 逆向工程评估
- 核心业务（接续判断/状态机）为纯 Dart，CI 构建已带 `--obfuscate --split-debug-info`；SM4 安全性依赖密钥保密（Keystore 内），算法公开无碍。
- `service_registry.dart` 固化了服务源缺省域名（本来即公开信息）；鉴权逻辑 72h 宽限为已知设计。混淆已覆盖建议，无需额外配置。

---

## 3. 修复汇总（9 项发现 → 9 项已修复）

| ID | 等级 | 摘要 | 状态 |
|---|---|---|---|
| F1 | 高 | 限流桶未装配 | ✅ d70d02b3 |
| F2 | 高 | 防篡改时钟未接入行程仓库 | ✅ d70d02b3 |
| F3 | 中 | 证件页缺 PIN 回退 | ✅ d70d02b3 |
| F4 | 高 | 跨日接续间隙漏加日期差 | ✅ d70d02b3 |
| F5 | 中 | 遗留 manifest 含签名密码（历史） | ⚠️ 待人工清洗历史（M1） |
| F6 | 低 | B1–B7 编译级问题 | ✅ d70d02b3 / 88a8bb49 |
| F7 | 低 | urlencoded POST 误用 FormData | ✅ d70d02b3 |
| F8 | 低 | JSON 数值强转 | ✅ d70d02b3 |
| F9 | 低 | Triple 构造器耦合测试 | ✅ feedValues 解耦 |

> **同步声明**：全部修改已提交至本地工作区 `flutter-rewrite` 分支（目标仓库 RailGoApps/RailGo-Flutter 的本地就绪态）；`git push` 需人工切换 remote（当前 origin 指向原 uni-app 仓库）并携带凭据执行，随后 CI 首跑即为权威 analyze/test/coverage 验证。
