// test/core/utils/railgo_time_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:railgo/core/utils/railgo_time.dart';

void main() {
  group('parseTimeToMinutes（含跨日语义）', () {
    test('常规时刻', () {
      expect(parseTimeToMinutes('06:30'), 390);
      expect(parseTimeToMinutes('23:59'), 1439);
      expect(parseTimeToMinutes('00:00'), 0);
    });
    test('跨日 25:30 → 1530（次日 01:30 的绝对分钟）', () {
      expect(parseTimeToMinutes('25:30'), 1530);
    });
    test('非法输入返回 null', () {
      expect(parseTimeToMinutes(null), isNull);
      expect(parseTimeToMinutes('-'), isNull);
      expect(parseTimeToMinutes(''), isNull);
      expect(parseTimeToMinutes('abc'), isNull);
      expect(parseTimeToMinutes('12'), isNull);
      expect(parseTimeToMinutes('99:00'), isNull);
    });
  });

  group('absoluteMinutes', () {
    test('day 偏移叠加', () {
      expect(absoluteMinutes(day: 0, hhmm: '01:10'), 70);
      expect(absoluteMinutes(day: 1, hhmm: '01:10'), 1510);
    });
    test('跨日小时与 day 字段兼容', () {
      // 25:30 = 25h30m → day+1 的 01:30
      expect(absoluteMinutes(day: 0, hhmm: '25:30'), absoluteMinutes(day: 1, hhmm: '01:30'));
    });
    test('缺失时刻返回 null', () {
      expect(absoluteMinutes(day: 0, hhmm: null), isNull);
    });
  });

  group('inferDayOffsets（基线 normalizeTimetable 等价移植）', () {
    test('夜车跨日累计', () {
      final offsets = inferDayOffsets([
        (arrive: null, depart: '22:00'),
        (arrive: '23:30', depart: '23:50'),
        (arrive: '01:10', depart: '01:12'),
        (arrive: '03:00', depart: null),
      ]);
      expect(offsets, [0, 0, 1, 1]);
    });
    test('白班车无跨日', () {
      final offsets = inferDayOffsets([
        (arrive: null, depart: '08:00'),
        (arrive: '09:00', depart: '09:02'),
        (arrive: '10:00', depart: null),
      ]);
      expect(offsets, [0, 0, 0]);
    });
    test('站内跨日（depart < arrive 再加一天）不污染后续判断', () {
      final offsets = inferDayOffsets([
        (arrive: null, depart: '23:50'),
        (arrive: '23:55', depart: '00:05'),
        (arrive: '02:00', depart: null),
      ]);
      expect(offsets, [0, 0, 1]);
    });
  });

  group('Asia/Shanghai 强制时区', () {
    test('UTC → 上海 +8', () {
      final t = nowShanghai(utcNow: DateTime.utc(2025, 6, 1, 16, 0));
      expect(t.year, 2025);
      expect(t.month, 6);
      expect(t.day, 2);
      expect(t.hour, 0);
    });
    test('ymdShanghai 格式 yyyymmdd', () {
      final s = ymdShanghai(DateTime.utc(2025, 6, 1, 15, 59));
      expect(s, '20250601');
      final s2 = ymdShanghai(DateTime.utc(2025, 6, 1, 16, 0));
      expect(s2, '20250602');
    });
  });
}
