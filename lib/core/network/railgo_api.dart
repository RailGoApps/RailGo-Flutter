// lib/core/network/railgo_api.dart
//
// RailGo 数据服务 API 客户端（V1 ×6 / V2 ×6 / EMU ×3 + 应用侧端点）。
// 端点与参数 100% 对齐基线 Baseline §3.2–§3.5（llms.txt + OpenAPI 文档 + 调用点三方实证）。
library;

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'service_registry.dart';

class RailGoApi {
  RailGoApi(this._client);
  final RailGoApiClient _client;

  // ─────────────── V1（llms.txt 文档 ID 366464494e0 等） ───────────────

  /// V1 车次查询：/api/train/query?train=G1 —— 交路/时刻表/里程（补全数据源）
  Future<Response<Map<String, dynamic>>> trainQueryV1(String train) =>
      _client.get<Map<String, dynamic>>(ServiceCode.train, '/api/train/query', query: {'train': train});

  /// V1 站到站：/api/train/sts_query?from=&to=&date=[&city=]
  Future<Response<Map<String, dynamic>>> stationToStation({
    required String fromTelecode,
    required String toTelecode,
    required String date,
    bool city = false,
  }) =>
      _client.get<Map<String, dynamic>>(ServiceCode.train, '/api/train/sts_query',
          query: {'from': fromTelecode, 'to': toTelecode, 'date': date, if (city) 'city': 'true'});

  /// V1 车站预选词：/api/station/preselect?keyword=
  Future<Response<List<dynamic>>> stationPreselect(String keyword) =>
      _client.get<List<dynamic>>(ServiceCode.station, '/api/station/preselect', query: {'keyword': keyword});

  /// V1 车站查询：/api/station/query?telecode=
  Future<Response<Map<String, dynamic>>> stationQuery(String telecode) =>
      _client.get<Map<String, dynamic>>(ServiceCode.station, '/api/station/query', query: {'telecode': telecode});

  /// V1 车次预选词：/api/train/preselect?keyword=
  Future<Response<List<dynamic>>> trainPreselect(String keyword) =>
      _client.get<List<dynamic>>(ServiceCode.train, '/api/train/preselect', query: {'keyword': keyword});

  /// V1 随机车次：/api/lucky（纪念车票定制；原 App 未接入，Flutter 版保留能力）
  Future<Response<Map<String, dynamic>>> luckyTrain() =>
      _client.get<Map<String, dynamic>>(ServiceCode.train, '/api/lucky');

  // ─────────────── V2 ───────────────

  /// V2 车次主数据：/api/v2/getTrainMain?trainNum=&date=（date 缺省今天）
  Future<Response<Map<String, dynamic>>> getTrainMain({required String trainNum, String? date}) =>
      _client.get<Map<String, dynamic>>(ServiceCode.trainV2, '/api/v2/getTrainMain',
          query: {'trainNum': trainNum, if (date != null && date.isNotEmpty) 'date': date});

  /// V2 检票口/停台/出站口：/api/v2/getExit?trainNum=&stationTelecode=&date=&kind=
  /// kind: arrival | departure（始发站用 departure —— 基线 trainResult 实证）
  Future<Response<Map<String, dynamic>>> getExit({
    required String trainNum,
    required String stationTelecode,
    required String date,
    required bool isDepartureStop,
  }) =>
      _client.get<Map<String, dynamic>>(ServiceCode.exit, '/api/v2/getExit', query: {
        'trainNum': trainNum,
        'stationTelecode': stationTelecode,
        'date': date,
        'kind': isDepartureStop ? 'departure' : 'arrival',
      });

  /// V2 车次正晚点：/api/v2/getTrainDelayAll?trainNum=&date=
  Future<Response<Map<String, dynamic>>> getTrainDelayAll({required String trainNum, String? date}) =>
      _client.get<Map<String, dynamic>>(ServiceCode.trainDelay, '/api/v2/getTrainDelayAll',
          query: {'trainNum': trainNum, if (date != null && date.isNotEmpty) 'date': date});

  /// V2 车站大屏：/api/v2/getStationBigScreen?stationTelecode=&kind=
  Future<Response<Map<String, dynamic>>> getStationBigScreen({
    required String stationTelecode,
    required String kind,
  }) =>
      _client.get<Map<String, dynamic>>(ServiceCode.bigScreen, '/api/v2/getStationBigScreen',
          query: {'stationTelecode': stationTelecode, 'kind': kind});

  /// V2 列车车厢图：/api/v2/getCoachPic?train=
  Future<Response<Map<String, dynamic>>> getCoachPic(String train) =>
      _client.get<Map<String, dynamic>>(ServiceCode.coach, '/api/v2/getCoachPic', query: {'train': train});

  /// V2 列车运行线路点：/api/v2/mapLine?train=（GCJ-02 坐标，需转 WGS-84）
  Future<Response<Map<String, dynamic>>> getMapLine(String train) =>
      _client.get<Map<String, dynamic>>(ServiceCode.mapLine, '/api/v2/mapLine', query: {'train': train});

  // ─────────────── EMU ───────────────

  /// EMU 动车组运行：/api/query?keyword=（车次或车组号）
  Future<Response<Map<String, dynamic>>> emuRun(String keyword) =>
      _client.get<Map<String, dynamic>>(ServiceCode.emuRun, '/api/query', query: {'keyword': keyword});

  /// EMU 配属预查询：/api/car/query?keyword=&keywordType=Number|Model
  Future<Response<Map<String, dynamic>>> emuAssignmentPre(String keyword, {required String keywordType}) =>
      _client.get<Map<String, dynamic>>(ServiceCode.emuAssignment, '/api/car/query',
          query: {'keyword': keyword, 'keywordType': keywordType});

  /// EMU 配属详情：/api/car/info?id=
  Future<Response<Map<String, dynamic>>> emuAssignmentInfo(String id) =>
      _client.get<Map<String, dynamic>>(ServiceCode.emuAssignment, '/api/car/info', query: {'id': id});

  // ─────────────── 应用侧端点（原 App 直接硬编码 host，此处统一走服务源） ───────────────

  /// 服务发现：gateway.zenglingkun.cn/api/v2/service_endpoints
  Future<Map<String, List<ServiceEndpoint>>> discoverServiceEndpoints() async {
    final resp = await _client.get<List<dynamic>>(ServiceCode.notice, '/api/v2/service_endpoints');
    return parseServiceEndpoints(resp.data ?? <dynamic>[]);
  }

  /// 公告：/api/v2/notice（[AD]/[PSAD]/[WAR] 前缀语义保留）
  Future<Response<List<dynamic>>> notices() =>
      _client.get<List<dynamic>>(ServiceCode.notice, '/api/v2/notice');

  /// 广告图：/api/v2/pic_ad
  Future<Response<List<dynamic>>> picAds() =>
      _client.get<List<dynamic>>(ServiceCode.notice, '/api/v2/pic_ad');

  /// 应用/库版本信息：/api/v2/info
  Future<Response<Map<String, dynamic>>> updateInfo() =>
      _client.get<Map<String, dynamic>>(ServiceCode.updateDb, '/api/v2/info');

  /// 离线库下载地址：/api/v2/url/db（约 50MB）
  Future<Response<Map<String, dynamic>>> offlineDbUrl() =>
      _client.get<Map<String, dynamic>>(ServiceCode.updateDb, '/api/v2/url/db');

  /// 软件包地址：/api/v2/url/pack/android
  Future<Response<Map<String, dynamic>>> androidPackUrl() =>
      _client.get<Map<String, dynamic>>(ServiceCode.updatePack, '/api/v2/url/pack/android');

  /// 个性化图标清单：/api/v2/cc
  Future<Response<List<dynamic>>> iconCatalog() =>
      _client.get<List<dynamic>>(ServiceCode.icon, '/api/v2/cc');

  /// 卡密鉴权：center.zenglingkun.cn/beta/api/check/<ver>?userid=&key=
  /// （72h 离线宽限逻辑在 core/security/auth_service.dart）
  Future<Response<Map<String, dynamic>>> checkAuth({
    required String version,
    required String userid,
    required String key,
  }) =>
      _client.getAbsolute<Map<String, dynamic>>(
        '$kAuthEndpointBase/$version',
        query: {'userid': userid, 'key': key},
      );

  // ─────────────── 外部第三方固定端点（基线 §3.5） ───────────────

  /// 车型众包图片：tp /api/{车型}.json（"重联"后缀需去除后作为路径段）
  Future<Response<Map<String, dynamic>>> carModelImage(String carModel) =>
      _client.getAbsolute<Map<String, dynamic>>(
        '${baseOf(ServiceCode.tp)}/api/${Uri.encodeComponent(carModel)}.json',
      );

  /// 鸣谢用户：feedback.railgo.dev/api/get_users
  Future<Response<List<dynamic>>> feedbackUsers() =>
      _client.getAbsolute<List<dynamic>>('https://feedback.railgo.dev/api/get_users');

  /// 赞助者：zz.railgo.dev/api/sponsors
  Future<Response<List<dynamic>>> sponsors() =>
      _client.getAbsolute<List<dynamic>>('https://zz.railgo.dev/api/sponsors');

  /// 配属查询（POST 表单，MoeFactory 数据）
  Future<Response<Map<String, dynamic>>> trainAssignmentQueryEmu(Map<String, dynamic> fields) =>
      _client.postFormAbsolute<Map<String, dynamic>>(
        'https://delay.data.railgo.zenglingkun.cn/api/trainAssignment/queryEmu',
        fields: fields,
      );

  /// 车模图库搜索：train.idcmoss.cn/api/model_search.php
  Future<Response<Map<String, dynamic>>> galleryModelSearch(Map<String, dynamic> query) =>
      _client.getAbsolute<Map<String, dynamic>>('https://train.idcmoss.cn/api/model_search.php', query: query);

  /// 车模图库照片：train.idcmoss.cn/api/model_photos.php
  Future<Response<Map<String, dynamic>>> galleryModelPhotos(Map<String, dynamic> query) =>
      _client.getAbsolute<Map<String, dynamic>>('https://train.idcmoss.cn/api/model_photos.php', query: query);

  String baseOf(String code) => _client.baseFor(code);
}
