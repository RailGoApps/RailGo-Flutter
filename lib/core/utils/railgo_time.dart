// lib/core/utils/railgo_time.dart
//
// 本地化 (l10n) 时间基线：强制 Asia/Shanghai (UTC+8, 无夏令时)。
// 兼容基线 scripts/trainPosition.js 的跨日语义：
//   - 解析 "HH:mm"（小时数可 ≥24，如 "25:30" → 次日 05:30）
//   - day 字段叠加跨日偏移
library;

/// 上海时区固定偏移（UTC+8）
const Duration kShanghaiOffset = Duration(hours: 8);

/// 当前上海时间
DateTime nowShanghai({DateTime? utcNow}) =>
    (utcNow ?? DateTime.now()).toUtc().add(kShanghaiOffset);

/// 上海日期的 yyyymmdd（车次查询 date 参数格式）
String ymdShanghai([DateTime? utcNow]) {
  final t = nowShanghai(utcNow: utcNow);
  return '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
}

/// 解析 "HH:mm" 为当日分钟数；支持跨日（"25:30" → 1530）。非法输入返回 null。
int? parseTimeToMinutes(String? timeStr) {
  if (timeStr == null) return null;
  final t = timeStr.trim();
  if (t.isEmpty || t == '-') return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || m < 0 || m > 59 || h < 0 || h > 48) return null;
  return h * 60 + m;
}

/// 以发车日零点（上海时间）为基准，把 (day, "HH:mm") 折算为绝对分钟数。
/// "HH:mm" 中的小时数可 ≥24（跨日语义，"25:30" 即 day+1 的 05:30，已含于返回值）。
/// 返回 null 表示该站无该时刻（如始发站无到达、终到站无出发）。
int? absoluteMinutes({required int day, required String? hhmm}) {
  final minutes = parseTimeToMinutes(hhmm);
  if (minutes == null) return null;
  return day * 24 * 60 + minutes;
}

/// 时刻表跨日语义（与基线 normalizeTimetable 等价）：按相邻站累计推导每站 day 偏移。
/// 输入 stops 需保持顺序；返回每站相对首站的偏移天数。
List<int> inferDayOffsets(List<({String? arrive, String? depart})> stops) {
  final offsets = List<int>.filled(stops.length, 0);
  var day = 0;
  int? prevDepartAbs;
  for (var i = 0; i < stops.length; i++) {
    final a = parseTimeToMinutes(stops[i].arrive);
    final d = parseTimeToMinutes(stops[i].depart);
    if (i > 0 &&
        a != null &&
        prevDepartAbs != null &&
        a + day * 1440 < prevDepartAbs) {
      day += 1;
    }
    offsets[i] = day;
    // 站内跨日（depart < arrive）
    var depAbs = d == null ? null : d + day * 1440;
    final arrAbs = a == null ? null : a + day * 1440;
    if (depAbs != null && arrAbs != null && depAbs < arrAbs) depAbs += 1440;
    prevDepartAbs = depAbs ?? arrAbs ?? prevDepartAbs;
  }
  return offsets;
}
