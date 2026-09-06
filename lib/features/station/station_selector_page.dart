// lib/features/station/station_selector_page.dart
//
// 车站选择器（基线 pages/station/commonSelect.vue 1:1 移植——Phase 4 清单第 2 项）：
//   关键字搜索（network → /api/station/preselect；local → SQLite LIKE）
//   类型徽章：客#114598 货#eeba67 高#c0392b 行#459811 运#5499c7
//   选中 pop 回填（原 resultPlace storage 键机制 → Flutter 用路由返回值）
library;

import 'package:flutter/material.dart';

import '../../core/network/railgo_api.dart';
import '../../core/network/rate_limiter.dart';
import '../../core/storage/offline_db.dart';
import '../../core/storage/settings_store.dart';

class StationPickResult {
  const StationPickResult({required this.name, required this.telecode});
  final String name;
  final String telecode;
}

class _StationItem {
  const _StationItem({required this.name, required this.telecode, this.pinyinTriple = '', this.types = const []});
  final String name;
  final String telecode;
  final String pinyinTriple;
  final List<String> types;
}

const Map<String, Color> badgeFlag = {
  '客': Color(0xFF114598),
  '货': Color(0xFFEEBA67),
  '高': Color(0xFFC0392B),
  '行': Color(0xFF459811),
  '运': Color(0xFF5499C7),
};

class StationSelectorPage extends StatefulWidget {
  const StationSelectorPage({
    super.key,
    required this.api,
    required this.settings,
    this.offlineDb,
    this.title = '选择车站',
  });

  final RailGoApi api;
  final SettingsStore settings;
  final OfflineDb? offlineDb;
  final String title;

  @override
  State<StationSelectorPage> createState() => _StationSelectorPageState();
}

class _StationSelectorPageState extends State<StationSelectorPage> {
  final _debouncer = Debouncer(const Duration(milliseconds: 260));
  final _controller = TextEditingController();
  List<_StationItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      _debouncer.run(_search);
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) {
      setState(() => _items = []);
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.settings.mode == AppMode.network) {
        final resp = await widget.api.stationPreselect(kw);
        final data = (resp.data ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((m) => _StationItem(
                  name: (m['name'] ?? '') as String,
                  telecode: (m['telecode'] ?? '') as String,
                  pinyinTriple: (m['pinyinTriple'] ?? '') as String,
                  types: ((m['type'] as List<dynamic>?) ?? const []).cast<String>(),
                ))
            .toList();
        setState(() => _items = data);
      } else {
        final db = widget.offlineDb;
        final esc = kw.replaceAll("'", "''");
        final rows = await db?.rawQuery(
          "SELECT name, telecode, pinyinTriple, type FROM stations WHERE name LIKE '%$esc%' OR pinyin LIKE '$esc%' OR pinyinTriple LIKE '$esc%' LIMIT 50",
        );
        setState(() => _items = (rows ?? [])
            .map((r) => _StationItem(
                  name: r['name'] as String? ?? '',
                  telecode: r['telecode'] as String? ?? '',
                  pinyinTriple: r['pinyinTriple'] as String? ?? '',
                ))
            .toList());
      }
    } on Exception {
      setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索车站名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                return ListTile(
                  title: Text('${item.name}站'),
                  subtitle: Text('${item.pinyinTriple}/-${item.telecode}', style: const TextStyle(fontSize: 12)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      for (final t in item.types)
                        if (badgeFlag.containsKey(t))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: badgeFlag[t], borderRadius: BorderRadius.circular(4)),
                            child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).pop(StationPickResult(name: item.name, telecode: item.telecode)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
