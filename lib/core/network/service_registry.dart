// lib/core/network/service_registry.dart
//
// 15 个服务源注册表（基线 Baseline §3.1 实证）+ 网关服务发现。
// 每个服务：用户可在 OOBE/设置中切换端点，持久化于本地设置表；
// 缺省回退域名与原项目完全一致。
library;

class ServiceCode {
  static const train = 'train';
  static const trainV2 = 'train_v2';
  static const station = 'station';
  static const emuRun = 'emu_run';
  static const emuAssignment = 'emu_assignment';
  static const icon = 'icon';
  static const updatePack = 'update_pack';
  static const updateDb = 'update_db';
  static const bigScreen = 'bigScreen';
  static const trainDelay = 'trainDelay';
  static const exit = 'exit';
  static const coach = 'coach';
  static const mapLine = 'mapLine';
  static const notice = 'notice';
  static const tp = 'tp';

  static const all = <String>[
    train,
    trainV2,
    station,
    emuRun,
    emuAssignment,
    icon,
    updatePack,
    updateDb,
    bigScreen,
    trainDelay,
    exit,
    coach,
    mapLine,
    notice,
    tp,
  ];
}

/// 服务元数据（code → 中文名 + 缺省 base），键值与原项目 oobe/source.vue serviceNameMap 对齐
const Map<String, ({String name, String defaultBase})> kServiceCatalog = {
  ServiceCode.train: (
    name: '车次查询',
    defaultBase: 'https://data.railgo.zenglingkun.cn'
  ),
  ServiceCode.trainV2: (
    name: '车次主数据',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.station: (
    name: '车站查询',
    defaultBase: 'https://data.railgo.zenglingkun.cn'
  ),
  ServiceCode.emuRun: (
    name: '动车组运行',
    defaultBase: 'https://emu.railgo.zenglingkun.cn'
  ),
  ServiceCode.emuAssignment: (
    name: '动车组配属',
    defaultBase: 'https://emu.railgo.zenglingkun.cn'
  ),
  ServiceCode.icon: (
    name: '个性化图标',
    defaultBase: 'https://gateway.zenglingkun.cn'
  ),
  ServiceCode.updatePack: (
    name: '软件更新',
    defaultBase: 'https://gateway.zenglingkun.cn'
  ),
  ServiceCode.updateDb: (
    name: '数据库升级',
    defaultBase: 'https://gateway.zenglingkun.cn'
  ),
  ServiceCode.bigScreen: (
    name: '车站大屏',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.trainDelay: (
    name: '列车正晚点',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.exit: (
    name: '检票口、停台、出站口',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.coach: (
    name: '车厢图',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.mapLine: (
    name: '线路点',
    defaultBase: 'https://rg-api.zenglingkun.cn'
  ),
  ServiceCode.notice: (
    name: '通知',
    defaultBase: 'https://gateway.zenglingkun.cn'
  ),
  ServiceCode.tp: (name: '图片', defaultBase: 'https://tp.railgo.zenglingkun.cn'),
};

/// 服务发现网关（硬编码，与原项目一致；鉴权域名见 kAuthEndpoint）
const String kServiceDiscoveryUrl =
    'https://gateway.zenglingkun.cn/api/v2/service_endpoints';
const String kAuthEndpointBase = 'https://center.zenglingkun.cn/beta/api/check';

class ServiceEndpoint {
  const ServiceEndpoint(
      {required this.code, required this.desc, required this.url});
  final String code;
  final String desc;
  final String url;
}

/// 服务源 URL 校验与归一化（审计 R-01：传输层防降级）。
///
/// 仅接受 https —— 服务发现/用户配置一旦注入 http:// 或其他协议，
/// 所有 API 流量（含卡密鉴权参数）将以明文出网。此函数是全部请求的
/// 统一收口：容忍首尾空白与尾斜杠，拒绝非 https、userinfo、空主机。
/// 非法输入抛 [FormatException]。
String sanitizeServiceBaseUrl(String raw) {
  var t = raw.trim();
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
    throw const FormatException('服务源仅支持 https:// 地址');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const FormatException('服务源地址不允许携带用户名密码');
  }
  if (uri.host.isEmpty) {
    throw const FormatException('服务源地址缺少主机名');
  }
  return t;
}

/// 解析 /api/v2/service_endpoints 返回：[{code:[{desc,url},...]},...]
Map<String, List<ServiceEndpoint>> parseServiceEndpoints(List<dynamic> raw) {
  final out = <String, List<ServiceEndpoint>>{};
  for (final item in raw) {
    if (item is! Map) continue;
    for (final entry in item.entries) {
      final code = entry.key as String;
      final list = <ServiceEndpoint>[];
      if (entry.value is List) {
        for (final ep in entry.value as List) {
          if (ep is Map && ep['url'] != null) {
            // 审计 R-01：非 https 端点直接丢弃（不进入可选列表）
            try {
              list.add(ServiceEndpoint(
                  code: code,
                  desc: (ep['desc'] ?? '') as String,
                  url: sanitizeServiceBaseUrl(ep['url'] as String)));
            } on FormatException {
              continue;
            }
          }
        }
      }
      out[code] = list;
    }
  }
  return out;
}
