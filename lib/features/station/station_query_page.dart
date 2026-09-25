// lib/features/station/station_query_page.dart
//
// 车站查询 Tab（用户 UX 要求：车站查询 + 站站查询合并为同一入口）。
//   分段一「车站」：预选词搜索 → 车站信息 + 途经车次（/api/station/query）
//   分段二「站到站」：出发/到达站 + 日期 → 直达车次列表（/api/train/sts_query）
//                     点击车次进入既有车次结果页查看全程时刻表。
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/network/railgo_api.dart';
import '../../core/network/rate_limiter.dart';
import '../../core/storage/settings_store.dart';
import '../../core/utils/railgo_time.dart';
import '../train/train_result_page.dart';
import 'station_query_models.dart';
import 'station_selector_page.dart';

class StationQueryPage extends StatefulWidget {
  const StationQueryPage(
      {super.key, required this.api, required this.settings});

  final RailGoApi api;
  final SettingsStore settings;

  @override
  State<StationQueryPage> createState() => _StationQueryPageState();
}

class _StationQueryPageState extends State<StationQueryPage> {
  int _segment = 0; // 0 车站 / 1 站到站

  // ── 车站模式状态 ──
  final _debouncer = Debouncer(const Duration(milliseconds: 260));
  final _controller = TextEditingController();
  List<_PreselectItem> _items = [];
  bool _searching = false;
  StationDetail? _detail;
  String? _detailError;

  // ── 站到站模式状态 ──
  StationPickResult? _from;
  StationPickResult? _to;
  String _dateYmd = ymdShanghai();
  List<StsRoute> _routes = const [];
  bool _stsLoading = false;
  String? _stsError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => _debouncer.run(_search));
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
      if (mounted) setState(() => _items = []);
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final resp = await widget.api.stationPreselect(kw);
      final items = (resp.data ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((m) => _PreselectItem(
                name: (m['name'] ?? '').toString(),
                telecode: (m['telecode'] ?? '').toString(),
                pinyinTriple: (m['pinyinTriple'] ?? '').toString(),
                types: ((m['type'] as List?) ?? const []).map(_s).toList(),
              ))
          .toList(growable: false);
      if (mounted) setState(() => _items = items);
    } on Exception {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadDetail(String telecode) async {
    final l10n = AppLocalizations.of(context);
    if (mounted) {
      setState(() {
        _detailError = null;
        _searching = true;
      });
    }
    try {
      final resp = await widget.api.stationQuery(telecode);
      final d = StationDetail.fromResponse(resp.data ?? {});
      if (mounted) setState(() => _detail = d);
    } on Exception {
      if (mounted) {
        setState(() => _detailError = l10n.loadFailedLabel);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickStation(bool isFrom) async {
    final l10n = AppLocalizations.of(context);
    final r = await Navigator.of(context).push<StationPickResult>(
      MaterialPageRoute<StationPickResult>(
        builder: (_) => StationSelectorPage(
          api: widget.api,
          settings: widget.settings,
          title: isFrom ? l10n.fromStationLabel : l10n.toStationLabel,
        ),
      ),
    );
    if (r == null) return;
    if (mounted) {
      setState(() {
        if (isFrom) {
          _from = r;
        } else {
          _to = r;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 14)),
    );
    if (d == null) return;
    final ymd =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    if (mounted) setState(() => _dateYmd = ymd);
  }

  Future<void> _querySts() async {
    final l10n = AppLocalizations.of(context);
    final from = _from;
    final to = _to;
    if (from == null || to == null || from.telecode == to.telecode) return;
    if (mounted) {
      setState(() {
        _stsLoading = true;
        _stsError = null;
      });
    }
    try {
      final resp = await widget.api.stationToStation(
        fromTelecode: from.telecode,
        toTelecode: to.telecode,
        date: _dateYmd,
      );
      final routes = parseStsRoutes(resp.data ?? <dynamic>[]);
      if (mounted) {
        setState(() => _routes = routes);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _stsError = l10n.loadFailedLabel;
          _routes = const [];
        });
      }
    } finally {
      if (mounted) setState(() => _stsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.store_outlined),
                label: Text(l10n.stationSegStation),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.route_outlined),
                label: Text(l10n.stationSegSts),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (s) => setState(() => _segment = s.first),
          ),
        ),
        Expanded(
          child: switch (_segment) {
            0 => _buildStationMode(l10n),
            _ => _buildStsMode(l10n),
          },
        ),
      ],
    );
  }

  Widget _buildStationMode(AppLocalizations l10n) {
    final d = _detail;
    if (d != null) {
      return _StationDetailView(
        detail: d,
        onBack: () => setState(() => _detail = null),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchStationHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        if (_detailError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_detailError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final item = _items[i];
              return ListTile(
                title: Text(item.name),
                subtitle: Text('${item.pinyinTriple} · ${item.telecode}',
                    style: const TextStyle(fontSize: 12)),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    for (final t in item.types)
                      if (badgeFlag.containsKey(t))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: badgeFlag[t],
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(t,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ),
                  ],
                ),
                onTap: () => _loadDetail(item.telecode),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStsMode(AppLocalizations l10n) {
    final from = _from;
    final to = _to;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StationField(
                        label: l10n.fromStationLabel,
                        text: from?.name,
                        onTap: () => _pickStation(true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.sync_alt),
                    ),
                    Expanded(
                      child: _StationField(
                        label: l10n.toStationLabel,
                        text: to?.name,
                        onTap: () => _pickStation(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_dateYmd == ymdShanghai()
                          ? l10n.todayLabel
                          : '${_dateYmd.substring(4, 6)}-${_dateYmd.substring(6)}'),
                      onPressed: _pickDate,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.search),
                      label: Text(l10n.stsQueryButton),
                      onPressed: from != null && to != null && !_stsLoading
                          ? _querySts
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_stsLoading) const LinearProgressIndicator(minHeight: 2),
        if (_stsError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_stsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (!_stsLoading &&
            _routes.isEmpty &&
            _stsError == null &&
            _from != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(l10n.stsEmpty)),
          ),
        for (final r in _routes)
          Card(
            child: ListTile(
              title: Text('${r.number} · ${r.fromDepart} → ${r.toArrive}'
                  '${r.dayDiff > 0 ? '  +${r.dayDiff}d' : ''}'),
              subtitle: Text('${r.type} · ${r.car} · ${r.passTime}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainResultPage(
                    keyword: r.number,
                    date: _dateYmd,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StationField extends StatelessWidget {
  const _StationField({
    required this.label,
    required this.text,
    required this.onTap,
  });

  final String label;
  final String? text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          text ?? label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: text == null ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _StationDetailView extends StatelessWidget {
  const _StationDetailView({required this.detail, required this.onBack});

  final StationDetail detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = detail;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.store_outlined),
          title: Text(d.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          subtitle:
              Text('${d.pinyinTriple} · ${d.telecode} · ${d.types.join('/')}'),
          trailing:
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row(l10n.stationBureauLabel, d.bureau),
                      _row(l10n.stationCityLabel, d.city),
                      _row(l10n.stationLevelLabel, d.level),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(l10n.passingTrains,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final t in d.passingTrains)
                ListTile(
                  dense: true,
                  title: Text('${t.number} · ${t.type}'),
                  subtitle: Text(
                      '${t.fromStation} → ${t.toStation} · ${t.arrive}/${t.depart}'),
                  trailing:
                      t.stopMinutes > 0 ? Text('${t.stopMinutes}min') : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(k), Text(v)],
        ),
      );
}

class _PreselectItem {
  const _PreselectItem({
    required this.name,
    required this.telecode,
    required this.pinyinTriple,
    required this.types,
  });

  final String name;
  final String telecode;
  final String pinyinTriple;
  final List<String> types;
}

String _s(Object? v) => v?.toString() ?? '';
