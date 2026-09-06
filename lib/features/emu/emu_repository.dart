// lib/features/emu/emu_repository.dart
//
// EMU 动车组查询（基线 emu/* 页 + llms.txt EMU 三接口）：
//   /api/query?keyword=（运行）｜/api/car/query?keyword=&keywordType=Number|Model（配属预查）｜/api/car/info?id=（配属详情）
library;

import '../../core/network/railgo_api.dart';

class EmuRunRecord {
  const EmuRunRecord(
      {required this.trainNum,
      required this.date,
      this.emuNo = '',
      this.note = ''});
  final String trainNum;
  final String date;
  final String emuNo;
  final String note;
}

class EmuAssignment {
  const EmuAssignment(
      {required this.id,
      required this.model,
      required this.bureau,
      this.homeDepot = '',
      this.extra = const {}});
  final String id;
  final String model;
  final String bureau;
  final String homeDepot;
  final Map<String, dynamic> extra;
}

enum EmuKeywordType { number, model }

class EmuRepository {
  EmuRepository(this._api);
  final RailGoApi _api;

  /// 运行查询：车次号（G1202）或车组号（5033）
  Future<List<EmuRunRecord>> runQuery(String keyword) async {
    final resp = await _api.emuRun(keyword);
    final data = resp.data;
    if (data == null || data['success'] != true) {
      return const [];
    }
    final list = (data['data'] as List<dynamic>? ?? []);
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => EmuRunRecord(
              trainNum: (m['train'] ?? m['trainNum'] ?? '').toString(),
              date: (m['date'] ?? '').toString(),
              emuNo: (m['emu'] ?? m['emuNo'] ?? '').toString(),
              note: (m['note'] ?? '').toString(),
            ))
        .toList();
  }

  /// 配属预查询：纯数字 → Number，否则 Model（基线 emu/result.vue 语义）
  Future<({List<EmuAssignment> items, int total})> assignmentPrequery(
      String keyword) async {
    final type = RegExp(r'^\d+$').hasMatch(keyword)
        ? EmuKeywordType.number
        : EmuKeywordType.model;
    final resp = await _api.emuAssignmentPre(keyword,
        keywordType: type.name[0].toUpperCase() + type.name.substring(1));
    final data = resp.data;
    if (data == null || data['success'] != true) {
      return (items: const <EmuAssignment>[], total: 0);
    }
    final list = (data['data'] as List<dynamic>? ?? []);
    final items = list
        .whereType<Map<String, dynamic>>()
        .map((m) => EmuAssignment(
              id: (m['id'] ?? m['emu'] ?? '').toString(),
              model: (m['model'] ?? '').toString(),
              bureau: (m['bureau'] ?? '').toString(),
              homeDepot: (m['homeDepot'] ?? m['depot'] ?? '').toString(),
              extra: Map<String, dynamic>.from(m),
            ))
        .toList();
    return (items: items, total: (data['count'] as int?) ?? items.length);
  }

  Future<EmuAssignment?> assignmentInfo(String id) async {
    final resp = await _api.emuAssignmentInfo(id);
    final data = resp.data;
    if (data == null || data['success'] != true) return null;
    final d = data['data'];
    if (d is! Map) return null;
    return EmuAssignment(
      id: (d['id'] ?? id).toString(),
      model: (d['model'] ?? '').toString(),
      bureau: (d['bureau'] ?? '').toString(),
      homeDepot: (d['homeDepot'] ?? '').toString(),
      extra: Map<String, dynamic>.from(d),
    );
  }
}
