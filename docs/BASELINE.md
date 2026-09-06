# 《RailGo 原有业务深度逆向分析文档 (Baseline)》

> **文档版本**：v1.3（Phase 1 产出并经人工确认进入 Phase 2；§10 含 4 项人工反馈采纳）  
> **分析对象**：RailGo 原项目（uni-app / Vue3），本地工作区 `D:\Codes\RailGo` 即其完整源码检出  
> **分析对象版本**：`2.0.4 Build 20004`（内部版本号 28）——取自 `App.vue` 与 `manifest.json`  
> **数据源**：① 本地真实源码（pages.json / manifest.json / package.json / scripts/* / pages/* / uni_modules/* / harmony-configs/*）② `https://api.railgo.dev/llms.txt` 实际抓取成功（HTTP 200, 2339 字节）③ llms.txt 索引的 **17 份 OpenAPI 接口文档全部实际抓取成功**（原始文件保存于 `.analysis/docs/`，可直接复核）  
> **证据等级标注**：✅ = 已读取源码逐行验证；🔗 = 已通过 grep 定位真实调用点验证；📄 = 仅 pages.json 注册 + 命名推断（未逐行读取，**不含功能编造**）

---

## 0. 重要事实纠偏（必须先读，直接影响 Phase 2/4 规格）

以下 6 项是与任务书（Phase 2/4 清单）假设不符的**真实代码证据**：

| # | 任务书假设 | 真实情况（证据） | 影响 |
|---|---|---|---|
| 1 | 代理网关为 `auth.railgo.**zhenglingkun**.cn` | 真实域名为 `center.zenglingkun.cn`（鉴权）与 `gateway.zenglingkun.cn`（服务发现）。全仓库 grep `zhenglingkun` **0 匹配**；`zenglingkun` 命中 40+ 处（manifest.json h5 proxy、App.vue、各页面）。注：manifest.json 中 h5 devServer 代理写作 `auth.railgo.zenglingkun.cn`，但实际鉴权调用统一走 `center.zenglingkun.cn/beta/api/check/` | Flutter 网络层域名必须以本文 §3.1 为准 |
| 2 | V2 车厢图/线路点需要"替代 **OpenLayers** 的地图组件" | `package.json` 确实声明 `ol: ^10.9.0`，但**全项目 0 处 import**（grep `from 'ol` = 0）。实际地图渲染是自研组件 `uni_modules/siji-tianditu`（天地图瓦片），由 `trainResult.vue` 调用 `drawRoute/drawMarkers/setCenter` | Flutter 端承接组件应对标"天地图自绘地图"，而非 OpenLayers |
| 3 | （Phase 2 §4.3）证件管理为原有功能 | 原项目 grep `证件/biometric/生物识别/fingerprint` = **0 匹配**。**完全新增功能** | 属新功能设计，无移植基线 |
| 4 | （Phase 2 §4.2）接续/换乘逻辑为原有功能 | 原项目 grep `换乘/接续/同车` = **0 匹配**。`route.vue` 仅为静态行程列表（长按删除），无任何换乘判断 | 属新功能设计，无移植基线 |
| 5 | （Phase 2 §4.5）传感器测速为兜底增强 | 原项目 grep `accelerometer` = **0 匹配**。`speed.vue` 测速**纯靠系统定位**（500ms 轮询 + 高/低精度切换，鸿蒙走 `railgo-location` UTS 原生） | 加速度计积分测速属新增；现有基线仅 GPS 测速 |
| 6 | 原项目具备 i18n（需 5 语言补齐） | grep `setLocale/getLocale/vue-i18n/$t(` = **0 匹配**，manifest `locale: zh-Hans`，全部文案中文硬编码 | 5 语言 i18n 属从零建设 |

另有一处待运行时确认：`api/README.md`（本地 Flask mock）提到 `crtracker.azteam.cn/api/query` 为"原项目查询接口"，但正式代码中 **0 处引用**（正式链路走 data.railgo.zenglingkun.cn），判定为历史遗留说明，非现行接口。

---

## 1. 项目身份与技术形态

| 项 | 值（证据） |
|---|---|
| 应用名 | RailGo 铁路行（manifest.json `name`） |
| AppID | `__UNI__1A91000`（uni-app）/ `com.azstudio.railgo`（Android/鸿蒙 bundleName） |
| 形态 | uni-app + Vue 3（`vueVersion: 3`），HBuilderX 工程（.hbuilderx/launch.json） |
| 目标平台 | Android、iOS、HarmonyOS（app-harmony 配置 + harmony-configs）、H5（devServer 代理）、微信/支付宝/百度/抖音等小程序壳（manifest 注册，无实质小程序代码） |
| 模块（manifest modules） | `SQLite`、`Geolocation`（system provider，iOS/Android） |
| Android minSdk | 21；URL Scheme：`railgo://`（App.vue onShow 解析 `railgo://pagePath?params` 并自动补 `date=yyyymmdd`） |
| iOS 隐私声明 | 定位三项均为"用于测速功能" |
| 鸿蒙权限（harmony-configs/module.json5） | `ohos.permission.INTERNET`、`APPROXIMATELY_LOCATION`、`LOCATION`（inuse） |
| 状态栏/主题 | 品牌蓝 `#114598`，自定义导航（`navigationStyle: custom`，titleNView false） |
| UI 体系 | 自建 `unix-ui`（ux-* 前缀，uvue 双端组件）+ uv-*/uni-* 组件库 + FirstUI 残留（fui-*） |

---

## 2. 真实页面路由矩阵（pages.json 全量 45 页，无 subPackages）

启动页 = pages 数组第一项 `pages/index/index`。所有页面 `navigationBarTitleText: ""`（自定义导航），全局导航背景 `#114598`。

| # | 路由 | 功能（证据等级） | 依赖 API / 存储 |
|---|---|---|---|
| 1 | `pages/index/index` | 首页：公告轮播（`[AD]/[PSAD]/[WAR]` 前缀分类）、广告图 Swiper（预加载测高）、版本更新弹窗、功能入口（✅） | `/api/v2/notice`、`/api/v2/pic_ad`（base: service_source_notice，默认 gateway.zenglingkun.cn） |
| 2 | `pages/emu/query` | 动车组综合查询入口，关键字 G1202/CR400BF/5033，页脚"数据来源: crh.lihugang.top & RailGo"（✅） | 无（跳转 result） |
| 3 | `pages/emu/result` | EMU 结果页：车次→运行查询；纯数字→keywordType=Number，否则 Model→配属查询；全量拉取+本地分页（✅） | `/api/query?keyword=`、`/api/car/query?keyword=&keywordType=`（emu.railgo.zenglingkun.cn） |
| 4 | `pages/about/about` | 关于页：版本、离线库版本、EULA/隐私/个性化/模式/服务源入口、重置 OOBE、Logo 点击彩蛋入口（✅） | 本地 storage |
| 5 | `pages/about/member` | 成员/鸣谢页：QQ 头像（q1.qlogo.cn）、数据源介绍表（RailGo.Parser 等）、赞助列表（🔗） | `feedback.railgo.dev/api/get_users`、`tp.railgo.zenglingkun.cn/api/user`、`zz.railgo.dev/api/sponsors` |
| 6 | `pages/about/eula` | 用户协议页（📄） | — |
| 7 | `pages/station/query` | 车站查询入口：经 commonSelect 选择回填，默认北京/BJP；"查询同城车站"开关**已被注释禁用**；页脚"数据来源: RailGo.Parser"（✅） | storage `station_query_field` |
| 8 | `pages/station/result` | 车站结果：车站详情 + 车站大屏 + 12306 休息室/便捷导航（🔗） | `/api/station/query?telecode=`、`/api/v2/getStationBigScreen?stationTelecode=&kind=`、`mobile.12306.cn/.../navigation/listInfo` |
| 9 | `pages/station/commonSelect` | **车站选择器**（非"同城映射器"）：关键字搜索（network→preselect / local→SQLite LIKE），类型徽章 客/货/高/行/运，选中回填 `resultPlace` 指定的 storage 键，供 station_query / train_sts 等复用（✅） | `/api/station/preselect?keyword=`（data.railgo.zenglingkun.cn）或本地 SQLite |
| 10 | `pages/train/query` | 车次+站到站双模式查询主页：自定义键盘输入、260ms 防抖预选词、查询历史、同城开关（`city=true`）传给站到站（✅） | `/api/train/preselect?keyword=` 或 SQLite `numberFull LIKE` |
| 11 | `pages/train/stsResult` | 站到站车次结果（🔗） | `/api/train/sts_query?from=&to=&date=[&city=true]` |
| 12 | `pages/train/trainResult` | **车次结果主页（最复杂页面）**：V2 主数据+V1 交路/里程合并；今日车次加载正晚点；停台/检票口/出站口（阈值 <N 站自动全量加载，否则手动）；车厢图；运行线路点地图（天地图+GCJ-02→WGS-84）；添加行程；查无此车→404（✅深度） | `/api/v2/getTrainMain`、`/api/train/query`、`/api/v2/getTrainDelayAll`、`/api/v2/getExit`、`/api/v2/mapLine`、`tp /api/{车型}.json` |
| 13 | `pages/about/egg` | 开发者个人彩蛋（长文《Die Verliebte von TKP30》，写入 `Funnyegg=true`）（✅） | storage |
| 14 | `pages/about/mode` | 使用模式切换：network 优先在线 / local 优先离线（下载约 50MB 流量提示弹窗）；`ol` 仅离线选项**已注释禁用**（✅） | storage `mode` |
| 15 | `pages/update/db` | 更新管理：软件本体（仅 Android 区块）+ 离线数据库双卡片，版本比对与下载跳转（✅） | `/api/v2/info`、`/api/v2/url/pack/android`、`/api/v2/url/db` |
| 16 | `pages/oobe/welcome` | OOBE 欢迎页（✅） | — |
| 17 | `pages/oobe/protocol` | OOBE 协议确认（📄） | — |
| 18 | `pages/oobe/auth` | OOBE 鉴权：QQ 号+卡密（🔗） | `center.zenglingkun.cn/beta/api/check/<ver>?userid=&key=` |
| 19 | `pages/oobe/download` | OOBE 离线库下载（约 50MB）（🔗） | `/api/v2/url/db`、`/api/v2/info` |
| 20 | `pages/oobe/mode` | OOBE 模式选择（📄，逻辑同 about/mode） | storage `mode` |
| 21 | `pages/about/individuation` | 个性化：动态图标（crh/first/girl/gold/green/passion/purple/red）下载与切换（🔗） | `gateway /api/v2/cc`（service_source_icon） |
| 22 | `pages/speed/speed` | 实时测速：系统定位 500ms 轮询、高/低精度切换、经纬度/海拔/半球/卫星数/定位方式展示；鸿蒙走 railgo-location UTS 原生；**无加速度计**（✅） | 系统定位 API |
| 23 | `pages/404/404` | 通用 404 页（📄） | — |
| 24 | `pages/assignment/query` | 动车组配属查询入口："数据来源: MoeFactory"，仅离线模式不可用（✅） | — |
| 25 | `pages/assignment/result` | 配属结果（POST 表单）（🔗） | `delay.data.railgo.zenglingkun.cn/api/trainAssignment/queryEmu` |
| 26 | `pages/about/sponsor` | 赞助页：ts.railgo.dev 纪念车票文创 / shop.railgo.dev 文创店 / zz.railgo.dev 赞助平台（部分注释隐藏）（🔗） | — |
| 27 | `pages/train/keyboard` | **12306 风格车次键盘组件页**：字母区 G/D（行1）C/K（行2）L/T（行3）Z/Y/S（行4）+ 数字 0-9 + ⌫；字母点击为**前缀替换**语义；确认键 emit confirm（✅） | props/emits |
| 28 | `pages/oobe/privacy` | OOBE 隐私确认（📄） | — |
| 29 | `pages/about/privacy` | 隐私政策页（📄） | — |
| 30 | `pages/about/UpdateInfo` | 更新日志（首页更新弹窗跳转目标）（🔗） | — |
| 31 | `pages/train/TrainPics` | 列车车厢图页（🔗） | `/api/v2/getCoachPic?train=`（service_source_coach，默认 rg-api.zenglingkun.cn） |
| 32 | `pages/404/newYear` | 新年彩蛋 404：王安石《元日》诗词 + B 站视频 webview（BV1ad4y1V7wb）+ "彩蛋"按钮（✅） | web-view |
| 33 | `pages/404/egg` | 烟花+打字机彩蛋：按 storage `search`（累计查询次数）触发（✅） | storage |
| 34 | `pages/route/route` | 旅途列表：卡片式行程、长按删除、提示"伙伴产品 RailLog"；**无换乘/接续/状态机逻辑**（✅） | storage 行程数组 |
| 35 | `pages/route/routeDetail` | 行程详情：时刻/运行/其他 三 Tab；按 from/toStation 过滤区间时刻表；tp 车厢图；交路车次跳转查询（✅） | `tp /api/{车型}.json` |
| 36 | `pages/route/addRoute` | 添加行程：V2+V1 合并（在线）或 SQLite（离线）；始发/终到站选择（终到须在始发后）；日期；座位 seat 字段（空串占位，**未见席位类型/车厢号结构化输入**）（✅） | 同 trainResult 主链路 |
| 37 | `pages/debug/debug` | 调试页（📄） | — |
| 38 | `pages/debug/menu` | 调试菜单：直连 train/station 查询接口（🔗） | `/api/train/query`、`/api/station/query` |
| 39 | `pages/simulate/trainScreen` | 列车信息屏模拟器：车厢号/中英文跑马灯/车内外温度/禁烟图标，可全屏，设置本地持久化（✅） | storage |
| 40 | `pages/emu/info` | EMU 详情：配属详情+运行记录+图片（🔗） | `/api/car/info?id=`、`/api/query`、`tp` |
| 41 | `pages/about/source` | 服务源管理：15 项服务逐项 picker 切换 + "全部选择首个服务源"（✅） | `gateway.zenglingkun.cn/api/v2/service_endpoints` |
| 42 | `pages/gallery/gallery` | 车模照片图库：瀑布流（custom-waterfalls-flow）、车厢内部/外部筛选、预览（🔗） | `train.idcmoss.cn/api/model_photos.php` |
| 43 | `pages/oobe/source` | OOBE 服务源强制配置：未配全则每次启动拦截（App.vue）（✅） | 同 41 |
| 44 | `pages/gallery/query` | 图库车型搜索（🔗） | `train.idcmoss.cn/api/model_search.php` |
| 45 | `pages/gallery/result` | 图库搜索结果（🔗） | 同上 |

---

## 3. 真实 API 能力矩阵

### 3.1 服务发现与网关架构（原项目核心网络设计）

- **服务端点发现**：`GET https://gateway.zenglingkun.cn/api/v2/service_endpoints` → 返回数组 `[{code: [{desc, url}, ...]}, ...]`（oobe/source.vue 实证）。
- **15 个服务 code**（App.vue onLaunch 完整性校验清单）：`train, train_v2, station, emu_run, emu_assignment, icon, update_pack, update_db, bigScreen, trainDelay, exit, coach, mapLine, notice, tp`
- **每项服务**：用户可选端点持久化于 `service_source_<code>`，**缺省回退域名**如下（grep 实证）：

| service code | 中文名（oobe/source.vue） | 缺省 base |
|---|---|---|
| train | 车次查询（V1） | `https://data.railgo.zenglingkun.cn` |
| train_v2 | 车次主数据（V2） | `https://rg-api.zenglingkun.cn` |
| station | 车站查询 | `https://data.railgo.zenglingkun.cn` |
| emu_run | 动车组运行 | `https://emu.railgo.zenglingkun.cn` |
| emu_assignment | 动车组配属 | `https://emu.railgo.zenglingkun.cn` |
| icon | 个性化图标 | `https://gateway.zenglingkun.cn` |
| update_pack | 软件更新 | `https://gateway.zenglingkun.cn` |
| update_db | 数据库升级 | `https://gateway.zenglingkun.cn` |
| bigScreen | 车站大屏 | `https://rg-api.zenglingkun.cn` |
| trainDelay | 列车正晚点 | `https://rg-api.zenglingkun.cn` |
| exit | 检票口、停台、出站口 | `https://rg-api.zenglingkun.cn` |
| coach | 车厢图 | `https://rg-api.zenglingkun.cn` |
| mapLine | 线路点 | `https://rg-api.zenglingkun.cn` |
| notice | 通知（公告+广告图共用） | `https://gateway.zenglingkun.cn` |
| tp | 图片 | `https://tp.railgo.zenglingkun.cn` |

### 3.2 V1 接口（llms.txt + OpenAPI 文档 + 调用点三方实证）

| 端点 | 名称 | 参数（OpenAPI 实证） | 调用点 |
|---|---|---|---|
| `GET /api/train/query` | 车次查询 | `train` | trainResult/addRoute（交路+时刻表补全）、debug/menu |
| `GET /api/train/sts_query` | 站到站车次查询 | `from, to, date, city`（city=同城，布尔） | stsResult |
| `GET /api/station/preselect` | 车站预选词 | `keyword` | commonSelect |
| `GET /api/station/query` | 车站查询 | `telecode` | station/result、debug/menu |
| `GET /api/train/preselect` | 车次预选词 | `keyword` | train/query |
| `GET /api/lucky` | 随机选取车次（纪念车票定制） | 无 | **App 内 0 调用点**（文档存在） |

### 3.3 V2 接口（llms.txt + OpenAPI 文档 + 调用点三方实证）

| 端点 | 名称 | 参数（OpenAPI 实证） | 调用点 |
|---|---|---|---|
| `GET /api/v2/getTrainMain` | 车次主数据（路局/车型/运行日/时刻表） | `trainNum, date`（date 缺省今天；当日不开行返回空） | trainResult、addRoute |
| `GET /api/v2/getExit` | 检票口、停台及出站口 | `trainNum, stationTelecode, date, kind`（kind: arrival/departure，始发站用 departure——代码实证） | trainResult |
| `GET /api/v2/getTrainDelayAll` | 车次正晚点（全部） | `trainNum, date` | trainResult（仅今日车次） |
| `GET /api/v2/getStationBigScreen` | 车站大屏 | `stationTelecode, kind` | station/result |
| `GET /api/v2/getCoachPic` | 列车车厢图 | `train` | TrainPics |
| `GET /api/v2/mapLine` | 列车运行线路点（GCJ-02 坐标，stations+train 段） | `train` | trainResult（地图） |

**应用侧 V2 端点**（不在 llms.txt，代码实证）：`/api/v2/service_endpoints`（服务发现）、`/api/v2/notice`、`/api/v2/pic_ad`、`/api/v2/info`、`/api/v2/url/db`、`/api/v2/url/pack/android`、`/api/v2/cc`（个性化图标清单）。

### 3.4 EMU 接口（llms.txt + OpenAPI 文档 + 调用点三方实证）

| 端点 | 名称 | 参数 | 调用点 |
|---|---|---|---|
| `GET /api/query` | 动车组运行（车次/车组） | `keyword` | emu/result、emu/info |
| `GET /api/car/query` | 配属预查询（预选词/验存在） | `keyword, keywordType`（Number/Model） | emu/result |
| `GET /api/car/info` | 配属详细信息 | `id` | emu/info |

### 3.5 外部第三方端点（代码实证，Phase 2 网络层须一并纳入）

| 域名/端点 | 用途 |
|---|---|
| `center.zenglingkun.cn/beta/api/check/<ver>?userid=&key=` | 卡密鉴权（App.vue + oobe/auth.vue；**72h 离线宽限**；当前版本 `nauth=false` 默认关闭强制鉴权） |
| `tp.railgo.zenglingkun.cn/api/{车型}.json` 与 `/api/user` | 车型图片众包（含 uploader_username）、鸣谢用户 |
| `delay.data.railgo.zenglingkun.cn/api/trainAssignment/queryEmu` | 配属查询（POST 表单，MoeFactory 数据） |
| `train.idcmoss.cn/api/model_search.php`、`model_photos.php` | 车模图库（搜索/照片，GET params） |
| `zz.railgo.dev/api/sponsors`、`feedback.railgo.dev/api/get_users` | 赞助者、反馈用户 |
| `mobile.12306.cn/wxxcx/.../navigation/listInfo` | 车站休息室/便捷导航（station/result） |
| `q1.qlogo.cn/g?b=qq&nk=` | QQ 头像（member 页） |

### 3.6 API 使用限制与合规基线（llms.txt《数据服务简介》原文实证）

1. 现阶段 **API 不设 key**；三"不得"：**不得违法用途、不得商业用途、不得公开接口中转**；
2. 公开服务中使用数据**必须显著标注数据来源 + RailGo 主站/文档链接**（大学毕业设计等实验性使用豁免）；
3. **2026.08.08 起已启用限速**：请求过快会被短时封 IP 甚至进 WAF 黑名单（Flutter 端必须做请求防抖/并发控制/缓存）；
4. 大批量取数应自部署 `RailGo-Parser`（github.com/RailGoApps/RailGo-Parser），而非爬 API；
5. 传参格式：布尔接受 `1/true/True/yes` 与 `0/false/False/no`；日期接受 `MMdd/MM.dd/MM-dd/yyyyMMdd/yyyy-MM-dd/yyyy.MM.dd`（前三默认当年）；
6. 领域概念：**车次 ID**（如 24000000G10L，勿作存储主键）、**复车次**（G1202/1203 同列车）、**同城车站（12306 人工维护）vs 同地车站（地级行政区）**、电报码例外（徐州东转义 `-UUH/`，传入时去转义符）；
7. 路局对照表（哈局B…宁局Z 共 24 项，含港铁X/广东城际U）已存 `.analysis/docs/9408882m0.md`，Flutter 端应内置；
8. 联系方式：QQ 群 652032716；services@railgo.dev。

---

## 4. 真实底层依赖矩阵

### 4.1 package.json（注：该文件被 fui-avatar 组件的 manifest 覆盖过，但其 dependencies 为真实安装集）

| 依赖 | 版本 | 实际使用情况 |
|---|---|---|
| `vue` | ^3.5.17 | ✅ 框架本体（Vue3） |
| `@vue/reactivity` | ^3.5.39 | ✅ commonSelect/trainResult 等（toRaw） |
| `axios` | ^1.10.0 | ⚠️ 未见直接 import（配套 adapter 存在） |
| `uniapp-axios-adapter` | ^0.3.2 | ⚠️ js_sdk 内有 zxiaofoo-uniapp-axios-adapter 副本，**页面 0 直接引用**；实际请求走自研 `scripts/req.js`（uni.request 封装的 uniGet/uniPost，模拟 axios 响应结构） |
| `ol` | ^10.9.0 | ❌ **0 处 import，纯残留声明** |

### 4.2 uni_modules（22 个，全部真实存在于仓库）

**业务关键**：`siji-tianditu`（天地图地图：mapUtils/drawRoute/drawMarkers/setCenter）、`railgo-location`（鸿蒙原生定位 UTS）、`railgo-dynamic-icon`（鸿蒙动态图标 UTS）、`custom-waterfalls-flow`（图库瀑布流）、`unix-ui`（自建 ux-* 设计系统，含 ux-header/ux-modal/ux-footer-bar 等 30+ 组件）、`lime-divider/lime-style/lime-shared`、`ima-icons` + `sn-uts-appicon`（Android 动态图标 UTS）。
**通用组件**：uni-badge/breadcrumb/calendar/data-checkbox/datetime-picker/easyinput/icons/indexed-list/link/list/load-more/popup/scss/section/table/transition、uv-badge/divider/icon/line/sticky/tabs/ui-tools、fui-avatar/fui-icon、liuyuno-tabs、back-header、diagram-calendar（交路日历图组件）。
**已内置未使用**：`laoqianjunzi-widget`（Android AppWidget 桌面小组件 UTS 插件，**页面 0 调用**——实时活动/小组件在原项目仅到此程度，iOS ActivityKit 0 迹象）。

### 4.3 js_sdk（2 个）

`xtshadow-axios`（axios→uni.request 适配器，**0 页面引用**）、`zxiaofoo-uniapp-axios-adapter`（同上，0 页面引用）。二者为历史方案残留，现行网络层为 `scripts/req.js`。

### 4.4 原生插件与安全

- `Ionic-Safe`（DCloud 市场插件 pid 2857，Android 云打包）：App 启动时 `getSignature` 获取签名 SHA1 与硬编码 `44:BB:F4:8A:47:EA:1F:D7:DE:00:BD:78:F1:26:BB:35:83:2B:C8:E0` 比对，失败弹"修改版软件"警告并退出；无签名直接退出（**防二次打包/防调试的第一道锁**）。
- 鸿蒙签名配置（manifest app-harmony.distribute.signingConfigs）内含 p12/p7b 路径与**加密存储的密码串**（已在仓库中，Phase 2 迁移时须改为 CI Secret 注入，严禁再入库）。

### 4.5 本地存储体系（三层）

1. **SQLite**（plus.sqlite，`_doc/railgo.sqlite`）：离线模式主数据。表结构键序（config.js 实证）：
   - `trains`：code, number, numberFull, numberKind, bureau, bureauName, type, runner, car, carOwner, diagram, timetable, spend, rundays, route, isTemp, isFuxing, diagramType（JSON 字段入库，读取时反序列化）
   - `stations`：telecode, pinyin, pinyinTriple, tmism, name, bureau, belong, lines, type, trainList, level, city, province
2. **jsonDB**（`plus.io` PRIVATE_DOC/railgo.json，H5 走 /data/railgo-db.json）：JSON 整库方案（含 `_index_trains` 索引），记录 dbSize/dbTable 到 storage；
3. **uni storage 键清单**（grep 全量实证，Flutter 迁移须全量对应）：`mode, oobe, islaunched, version, versionText, NeedAuth, nauth, jqok, AuthTime, qq, key, beta, DBerror, search, Funnyegg, nowIcon, offlineDataVersion, offlineDataVersionText, showUpdateWelcome, showCustomUpdatePopup, dbSize, dbTable, station_query_field, train_sts_fieldA, train_sts_fieldB, gallery_model_info, ol, service_source_*（15 个）`。

### 4.6 静态资源要点

`static/offline/stations.json`（离线车站兜底表）、`static/bureauLogo/{B,H,N,Q}.png`（仅 4 个路局 Logo，其余缺失→Flutter 需补全或占位）、`static/trainHead/`（CAR_PERFORMANCE 引用 30+ 车型头图，**目录未随仓库提交**，Phase 2 需重新采买/绘制资源）、字体 din1451.ttf/hmsans.ttf/mdicon.ttf（数字等宽/鸿蒙字体/MD 图标）。

---

## 5. 核心业务逻辑逆向（运行时行为）

### 5.1 启动链路（App.vue onLaunch，顺序实证）
1. `checkSignature()`（Ionic-Safe 验签，失败即退出）→ 2. 首启标记/版本迁移（version_number 28 比对→showUpdateWelcome）→ 3. `NeedAuth` 为真时 `check()` 卡密鉴权（成功写 jqok=true；失败清 oobe 重回 OOBE；**网络异常时若距上次成功鉴权 <72h 放行"离线鉴权"，≥72h 强制重鉴权**）→ 4. OOBE 未完成→welcome；完成但 15 项服务源有缺→强拦 `pages/oobe/source` → 5. mode=local 则 `loadDB()` 打开 SQLite → 6. onShow 解析 `railgo://` URL Scheme 深链（自动补 date）。

### 5.2 查询主链路与降级策略（trainResult 实证）
- **在线模式**：V2 `getTrainMain` 为主数据（**失败/当日不开行→直接 404，不再回退 V1**）→ V1 `/api/train/query` 补交路+里程（**失败仅告警，不阻塞**）→ 按 stationTelecode 映射合并 distance/speed → 仅今日车次追加正晚点+停台（停台站数 < 阈值自动全量，否则手动批量）。
- **离线模式**（isOnlyOfflineMode）：SQLite 直查，跳过一切网络附加数据。
- **失败兜底**：正晚点/停台/图片失败均静默降级为空，不崩溃；主数据 catch 后重置卡片并跳 404。

### 5.3 地图与位置（trainResult + scripts 实证）
`mapLine` 返回 GCJ-02 → `scripts/coord_transform.js` 转 WGS-84 → `siji-tianditu` 绘制线路+站点标记+居中；`scripts/trainPosition.js` 提供**纯时间驱动**的列车位置估算：跨日 dayOffset 累计算法（非相邻比较）+ 发车日对齐（-1/0/+1 天候选）+ **梯形加减速模型**（按区间均速分档 accelRatio 0.08~0.18）。——这与 Phase 2 §4.1"纯离线时间驱动状态机"高度同源，可直接作为 Flutter 状态机的算法基线。

### 5.4 更新体系
软件本体（Android only）：`/api/v2/info` 比对→`/api/v2/url/pack/android` 取包；数据库：`/api/v2/url/db` 取 SQLite 包（约 50MB，流量提醒）。更新弹窗经 storage `showCustomUpdatePopup` 跨页触发。

### 5.5 彩蛋触发
`search` 计数（每次成功查询递变）→ `pages/404/egg` 烟花；新年期间 404 跳 `newYear`；about 页 Logo 连点→`about/egg`（Funnyegg）。Phase 4 要求保留的彩蛋页全部真实存在（共 3 个）。

---

## 6. Phase 2 规格对照结论（移植 vs 新增）

| Phase 2 模块 | 定性 | 基线可用资产 |
|---|---|---|
| 行程状态机（4 状态） | **新增**（原 route 无状态机），但 trainPosition.js 的跨日对齐+梯形模型可复用为算法基线 | scripts/trainPosition.js |
| 接续行程逻辑 | **新增**（0 匹配）；"同城/同地车站"**数据概念**已由 API 提供（llms.txt 概念节 + city 参数） | llms.txt §同城/同地 |
| 证件管理 SM4+Passkey | **全新增**（0 匹配） | 无 |
| Live-Push 实时活动 | **新增**（原仅一个未被调用的 Android AppWidget 插件；iOS/HarmonyOS 0 迹象） | laoqianjunzi-widget 可作 Android 参照 |
| 传感器积分测速 | **新增**（0 匹配）；原测速=系统定位轮询 | speed.vue 的精度切换/卫星数 UI 可参照 |
| 5 语言 i18n | **从零新增**（0 匹配） | 无 |
| 车次键盘 | **移植** | keyboard.vue（键位布局+前缀替换语义完整可抄） |
| 车站选择器 | **移植**（注意：它是通用选择器+回填机制，"同城"在站到站 city 参数） | commonSelect.vue |
| 数据库更新/修复 | **移植** | update/db.vue + /api/v2/url/db |
| 彩蛋页 | **移植**（404/egg、404/newYear、about/egg） | 三个 .vue |
| OOBE 全流程 | **移植** | 7 页 + 15 服务源强检 |
| 服务源选择/网关 | **移植**（域名以本文 §3.1 为准） | oobe/source.vue |
| 鉴权（72h 宽限） | **移植**（nauth 当前=false） | App.vue check() |

---

## 7. [无法读取，待人工补充] 清单（诚实声明）

1. **GitHub 在线仓库元数据**（RailGoApps/RailGo 默认分支/最新 commit、RailGo-Apps/RailGo-Flutter 目标仓库是否存在及其现状）：本机 schannel TLS 凭据故障（SEC_E_NO_CREDENTIALS）导致 GitHub API 不可达；api.railgo.dev 经 Node/OpenSSL 抓取成功，故 API 侧不受影响。本地源码为最权威基线，GitHub 仅缺"本地检出是否落后于远端"的核对。**待人工补充**：本地检出 commit 与远端 HEAD 的比对。
2. `service_endpoints` 的**实时返回内容**（各服务当前可用端点全集）：需运行时请求（含 WAF 风险），未在分析中触发；本文仅固化代码中的缺省域名。
3. `static/trainHead/` 车型头图资源：仓库中缺失（CAR_PERFORMANCE 引用 30+ 文件不存在于 static/）。
4. `api/` 本地 Flask mock 的 app.py：README 引用 `python app.py` 但仓库内**无 app.py 文件**（仅 README/requirements/test_api.py）。
5. llms.txt《常用对照表》官方自注"（待补充）"，路局表之外的字段对照未来可能扩充。

---

## 8. Phase 4 清单预核对（基线事实版）

- [x] `pages/train/keyboard`：真实存在，键位 G/D/C/K/L/T/Z/Y/S+数字+⌫，前缀替换语义（✅已读源码）
- [x] `pages/station/commonSelect`：真实存在，通用车站选择器+storage 回填（resultPlace 机制）；同城能力在站到站 `city=true` 参数，**非本地映射表**
- [x] `pages/update/db`：真实存在，软件+数据库双更新卡
- [x] `pages/404/egg` 与 `pages/404/newYear`：真实存在（另有第三个彩蛋 `pages/about/egg`）
- [x] V2 车厢图（getCoachPic + tp 众包图）与线路点（mapLine）：真实存在；承接组件为**自研天地图 siji-tianditu**（OpenLayers 0 引用）
- [x] 代理网关：真实为 `gateway.zenglingkun.cn`（服务发现）+ `center.zenglingkun.cn`（鉴权）；**`zhenglingkun` 拼写不存在**
- [x] i18n：原项目**无**，5 语言为从零新增
- [x] 容灾降级：V1 补全失败静默、正晚点/停台失败静默、72h 鉴权宽限、H5/APP 双通道、SQLite/jsonDB 双库——已有零散实现，未经测试体系验证（原项目**无任何自动化测试**，Phase 2 CI 属从零建设）
- [x] 法律文档：原项目有 eula.vue/privacy.vue 页面（内容未逐行核对，📄级），LICENSE/EULA/Privacy 的 Phase 2 版本需按任务书 §5 全新生成

---

## 9. 原始证据索引（可复核）

- llms.txt 全文：`.analysis/llms.txt`
- 17 份 OpenAPI 接口文档：`.analysis/docs/*.md`（文件名即 llms.txt 中的文档 ID）
- 本文档所有行号引用均可在工作区对应文件直接 grep 复核

> **Phase 1 完成声明**：本文档全部内容基于本地真实源码与真实抓取的 API 文档，未编造任何页面、接口或依赖；无法核实之处均已按约定标注"[无法读取，待人工补充]"。

---

## 10. v1.1 修订记录（人工反馈采纳）

| # | 反馈内容（人工提供） | 采纳与基线影响 |
|---|---|---|
| 1 | axios 对部分请求体过短的请求容易发生错误 | 该已知缺陷正是原项目在 `js_sdk` 中 vendored `xtshadow-axios` 与 `zxiaofoo-uniapp-axios-adapter` 两个适配器却**双双 0 引用**、最终以自研 `scripts/req.js`（uni.request 直封）替代的根因（见 §4.1/§4.3）。**Phase 2 约束**：Flutter 网络层使用 Dio 时须显式处理 GET 无请求体/超短请求体场景的 Content-Length 与 header 行为，并编写针对空/短 body 的单元测试，防止复刻同类缺陷 |
| 2 | 目标仓库为 `https://github.com/RailGoApps/RailGo-Flutter`（org: `RailGoApps`，与原项目同组织；任务书中 `RailGo-Apps` 为笔误） | 已更正 Phase 2 目标仓库。Phase 3 的"同步至目标仓库"以此地址为准 |
| 3 | 检查 `D:\Codes\skills` 技能库 | 盘点结果（共 406 文件）：**采纳 `md3e-skill`**（Material 3 Expressive 完整设计规范：48+ 色彩角色/design-tokens/MotionScheme/FloatingToolbar/FAB Menu/FlexibleBottomAppBar 等组件官方规格/种子色主题生成脚本）作为 Phase 2 Android 端（Material 3 Expressive + 浮动底栏）的**设计规格参考源**——其规格层可移植至 Flutter Material 3 实现；`Android_Skills`（AGP9 迁移）备用于 Android 工程壳构建；其余（docx/pdf/Openai-.NET/gcloud/动画类）与本项目无关 |
| 4 | 补充检查 `skills/skills/skills/apple-design` | **采纳**：Apple 流体界面设计原则（WWDC Designing Fluid Interfaces：即时响应/1:1 直接操纵/可中断动画/弹簧物理——damping ratio + response 双参数、具体参数表 Move 1.0/0.4、Drawer 0.8/0.3/速度交接）。虽为 Web 载体翻译版，但**原理层直接映射 Flutter `SpringSimulation`/`CupertinoFullscreenDialogTransition`**，作为 Phase 2 iOS(Cupertino) 端交互规范参考源（与 md3e-skill 分别覆盖 Android/iOS 两端设计基线） |

> 修订后文档重新挂起，等待人工回复"确认进入 Phase 2"。
