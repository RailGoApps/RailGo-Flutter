// lib/features/oobe/version_compare.dart
//
// 版本号比较（纯函数，可单测）：
//   网关返回 "pack":"2.0.6 Build 20006" 这类"语义化版本 + 构建串"格式，
//   提取首个 x.y.z 三元组逐段比较；无法解析时按"非更新"处理（不误报）。
library;

/// [latest] 是否严格新于 [current]
bool isNewerVersion(String latest, String current) {
  final l = versionTuple(latest);
  final c = versionTuple(current);
  if (l == null || c == null) return false;
  for (var i = 0; i < 3; i++) {
    if (l[i] != c[i]) return l[i] > c[i];
  }
  return false;
}

/// 提取首个 x.y.z 三元组；无匹配返回 null
List<int>? versionTuple(String s) {
  final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(s);
  if (m == null) return null;
  return [
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  ];
}
