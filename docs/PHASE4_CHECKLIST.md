# 《Phase 4 · 1:1 业务对照审查清单》

> 对照基线：`docs/BASELINE.md` v1.3（45 页路由矩阵 / 15 API 端点 / 依赖矩阵，全部实证）
> 审查对象：`flutter-rewrite` @ `88a8bb49`

## 任务书清单逐项核对

| # | 任务书要求 | 状态 | Flutter 承接物 | 基线对照 |
|---|---|---|---|---|
| 1 | `pages/train/keyboard` 自定义数字键盘完美重构 | ✅ | `lib/widgets/train_keyboard.dart` | 键位 G/D,C/K,L/T,Z/Y/S + 数字 + ⌫ 与基线逐键一致；字母前缀替换语义 1:1；确认键回调 |
| 2 | `pages/station/commonSelect` 同城/同地车站选择器 | ✅ | `lib/features/station/station_selector_page.dart` | 搜索防抖 260ms（基线同值）；客/货/高/行/运徽章五色一致；选中回填（resultPlace storage → 路由返回值）；"同城"能力如基线一样由站到站 `city` 参数承载（api_client.stationToStation） |
| 3 | `pages/update/db` 数据库更新/修复机制 | ✅ | `lib/features/oobe/update_page.dart` + `offline_db.dart`(损坏→内存兜底) | 软件/数据库双卡片、`/api/v2/info`+`/api/v2/url/db`+`/api/v2/url/pack/android` 三端点对齐 |
| 4 | `pages/404/egg`、`pages/404/newYear` 彩蛋保留重构 | ✅ | `lib/features/oobe/eggs.dart`（含第三个 about/egg） | 烟花+打字机 / 《元日》诗词+视频入口 / Funnyegg 长文彩蛋 三件全保留 |
| 5 | V2 车厢图与运行线路点的 UI 承接组件 | ✅ | `coach_pic_page.dart`（getCoachPic+tp 双源）+ `route_map.dart`（自绘多段线路+站点标记，GCJ-02→WGS-84 坐标转换移植自基线 coord_transform.js）+ `train_result_page.dart` | 基线承接物为自研天地图组件（**OpenLayers 实为 0 引用**，Baseline §0/#2）；Flutter 一期以无依赖自绘承接，flutter_map+天地图瓦片列为增强 |
| 6 | 代理网关逻辑在网络层正确处理 | ✅ | `service_registry.dart`（15 服务源注册表+缺省域名+service_endpoints 发现+用户切换持久化） | 域名纠偏：真实为 `gateway.zenglingkun.cn`/`center.zenglingkun.cn`（任务书 zhenglingkun 系笔误）；鉴权 72h 宽限移植（auth_service.dart） |
| 7 | 5 种语言国际化文件完整生成 | ✅ | `lib/core/l10n/app_{zh,zh_HK,ja,en,ko}.arb` ×32 键（JSON 校验通过） | 原项目**无 i18n**（0 匹配）；注：韩语 locale 标准码为 `ko`（`kr` 为卡努里语），已按标准实现 |
| 8 | 容灾降级逻辑经测试验证 | ✅ | 11 个测试文件：状态机边界/跨日/脏数据、接续 4 规则、SM4 国标向量+错误密钥、时钟跳变、令牌桶/闸门、PIN 哈希、证件门禁拒绝、传感器异常输入、OOBE 源完整性、坐标转换 | CI `test` job 强制 core 覆盖率 ≥80% |
| 9 | 法律文档（LICENSE/EULA/Privacy）准确生成 | ✅ | `LICENSE.md` + `assets/docs/{eula,privacy,permissions,about}.md` | EU 禁令与跨境条款**逐字嵌入**（程序化校验通过）；PIPL 权限逐项降级；数据来源 railgo.dev 显著标注 ×5 处 |

## 诚实声明：本期未做的 1:1 页面（列入下一迭代）
基线 45 页中，以下页面**尚未**在 Flutter 侧重建 UI（服务层/仓储已就绪）：
`stsResult`（站到站结果）、`station/result`（车站详情+大屏+12306 休息室）、`emu/*`（EMU 三页 UI）、`gallery/*`（车模图库）、`simulate/trainScreen`（列车信息屏模拟器）、OOBE 欢迎流 7 页 UI（门禁逻辑已就绪）、服务源选择页 UI、`debug/*`。
> 上述页面在任务书 Phase 4 九项清单之外，但属"1:1 重构"的完整范围，已在路线图中排期。
