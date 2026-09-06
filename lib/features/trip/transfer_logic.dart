// lib/features/trip/transfer_logic.dart
//
// 接续行程判断（Phase 2 §4.2，全部为原项目不存在的新增能力——见 Baseline §0/#4）
//
// | 类型       | 判断条件                                   | 提示规则 |
// | 同站换乘   | 前程到达站 == 后程出发站                    | < 20min → "换乘紧张" |
// | 同城异站   | 两站属同一同城组（12306 同城车站表/API city）| < 75min → "异站换乘 请快速通行 为安检 检票留足大于15分钟时间" |
// | 同车接续   | 车次号相同 + 到达站==出发站 + 到达日==出发日  | 到站前 10min → "同车接续，请确认是否需要换座" |
// | 最大间隔   | 换乘间隔 > 18h（默认，用户可调，上限 24h）    | 断开接续，视为独立行程 |
library;

/// 行程段（接续判断的最小字段集）
class TripLeg {
  const TripLeg({
    required this.trainNum,
    required this.departureStation,
    required this.arrivalStation,
    required this.departAbsMinutes,
    required this.arriveAbsMinutes,
    this.arriveDay = 0,
    this.departDay = 0,
    this.seat,
  });

  final String trainNum;
  final String departureStation;
  final String arrivalStation;

  /// 相对同一基准日零点的绝对分钟数（含跨日）
  final int departAbsMinutes;
  final int arriveAbsMinutes;
  final int arriveDay;
  final int departDay;
  final SeatInfo? seat;
}

/// 同车接续座位信息（用户手动输入，任务书 §4.2）
class SeatInfo {
  const SeatInfo({this.carNo, this.seatNo, this.seatClass = SeatClass.second});

  final String? carNo;
  final String? seatNo;
  final SeatClass seatClass;
}

enum SeatClass { business, first, second, noSeat, other }

/// 同城车站解析器：返回车站所属同城组标识（如 "重庆市城区"）；不同组返回不同标识。
/// 数据源：离线库 stations.city（基线 KEYS_STRUCT_STATIONS）或 API 同城概念。
typedef CityGroupResolver = String? Function(String stationName);

enum TransferType { sameTrain, sameStation, sameCity, plainConnection, none }

class TransferAdvice {
  const TransferAdvice({
    required this.type,
    required this.gapMinutes,
    this.warning,
    this.message,
    this.promptAtAbsMinutes,
  });

  final TransferType type;
  final int gapMinutes;
  /// 非空表示需要向用户示警的紧迫提示
  final String? warning;
  /// 常规提示（如同车接续的换座确认）
  final String? message;
  /// 应弹出 message 的时刻（绝对分钟；同车接续 = 到站前 10min）
  final int? promptAtAbsMinutes;
}

/// 默认最大换乘间隔（小时），用户可在设置中调整，上限 24。
const int kDefaultMaxTransferHours = 18;
const int kMaxTransferHoursLimit = 24;
const int kSameStationTightMinutes = 20;
const int kSameCityTightMinutes = 75;
const int kSameTrainPromptAheadMinutes = 10;

/// 评估两段行程的接续关系。gap > maxTransferHours*60 时返回 type=none（断开接续）。
TransferAdvice evaluateTransfer(
  TripLeg prev,
  TripLeg next, {
  CityGroupResolver? cityOf,
  int maxTransferHours = kDefaultMaxTransferHours,
}) {
  final gap = next.departAbsMinutes - prev.arriveAbsMinutes;
  if (gap > maxTransferHours * 60) {
    return TransferAdvice(type: TransferType.none, gapMinutes: gap, message: '换乘间隔过长，已断开接续，视为独立行程');
  }
  if (gap < 0) {
    return const TransferAdvice(type: TransferType.none, gapMinutes: -1, message: '行程时间重叠，不构成接续');
  }

  final sameStation = prev.arrivalStation == next.departureStation;
  final sameCity = !sameStation &&
      cityOf != null &&
      cityOf(prev.arrivalStation) != null &&
      cityOf(prev.arrivalStation) == cityOf(next.departureStation);
  final sameTrain = prev.trainNum == next.trainNum &&
      sameStation &&
      prev.arriveDay == next.departDay;

  if (sameTrain) {
    return TransferAdvice(
      type: TransferType.sameTrain,
      gapMinutes: gap,
      message: '同车接续，请确认是否需要换座',
      promptAtAbsMinutes: prev.arriveAbsMinutes - kSameTrainPromptAheadMinutes,
    );
  }
  if (sameStation) {
    return TransferAdvice(
      type: TransferType.sameStation,
      gapMinutes: gap,
      warning: gap < kSameStationTightMinutes ? '换乘紧张' : null,
    );
  }
  if (sameCity) {
    return TransferAdvice(
      type: TransferType.sameCity,
      gapMinutes: gap,
      warning: gap < kSameCityTightMinutes ? '异站换乘 请快速通行 为安检 检票留足大于15分钟时间' : null,
    );
  }
  return TransferAdvice(type: TransferType.plainConnection, gapMinutes: gap);
}

/// 校验用户设置的最大换乘时间（1..24h）
int clampMaxTransferHours(int hours) {
  if (hours < 1) return 1;
  if (hours > kMaxTransferHoursLimit) return kMaxTransferHoursLimit;
  return hours;
}
