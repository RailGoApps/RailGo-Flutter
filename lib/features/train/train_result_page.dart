// lib/features/train/train_result_page.dart
//
// 车次结果页（基线 pages/train/trainResult.vue 的第一期等价物）：
//   V2 主数据 + V1 交路/里程合并（TrainRepository.fetchOnline，失败/不开行 → 404 语义提示）
//   车厢图（CoachPicPage）与线路点（RouteLineMapView）承接入口；可加入旅途。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/utils/coord_transform.dart';
import '../../core/utils/railgo_time.dart';
import '../../main.dart';
import '../home/home_page.dart';
import '../trip/trip_state_machine.dart';
import '../trip/trip_store.dart';
import 'coach_pic_page.dart';
import 'route_map.dart';
import 'train_repository.dart';

class TrainResultPage extends ConsumerStatefulWidget {
  const TrainResultPage({super.key, required this.keyword, this.date});
  final String keyword;
  final String? date;

  @override
  ConsumerState<TrainResultPage> createState() => _TrainResultPageState();
}

class _TrainResultPageState extends ConsumerState<TrainResultPage> {
  late Future<TrainDetail> _future;
  bool _added = false;

  TrainRepository _repo() => TrainRepository(ref.read(railGoApiProvider));

  @override
  void initState() {
    super.initState();
    _future = _repo().fetchOnline(trainNum: widget.keyword, date: widget.date);
  }

  Future<void> _addToTrips(TrainDetail d) async {
    final repo = ref.read(tripRepoProvider);
    await repo.add(StoredTrip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      trainNum: d.trainNum,
      dateYmd: widget.date?.replaceAll(RegExp(r'[^0-9]'), '') ?? ymdShanghai(),
      stops: [
        for (final s in d.stops)
          TripStop(
            station: s.station,
            telecode: s.stationTelecode,
            arrive: s.arrive == '-' ? null : s.arrive,
            depart: s.depart == '-' ? null : s.depart,
            day: s.day,
          ),
      ],
    ));
    if (mounted) setState(() => _added = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.keyword)),
      body: FutureBuilder<TrainDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // 审计 U-01：区分"车次不存在"与"网络故障"——
            // 离线/弱网误报 404 会导致用户做出错误出行决策。
            final error = snap.error;
            final notFound = error is TrainNotFoundException ||
                (error is DioException &&
                    error.type == DioExceptionType.badResponse &&
                    error.response?.statusCode == 404);
            final (headline, message, icon) = notFound
                ? ('404', '车次不存在或当日不开行', Icons.search_off)
                : switch (error) {
                    DioException(
                      type: DioExceptionType.connectionTimeout ||
                          DioExceptionType.sendTimeout ||
                          DioExceptionType.receiveTimeout
                    ) =>
                      ('!', '网络连接超时，请检查网络后重试', Icons.wifi_off),
                    DioException(type: DioExceptionType.connectionError) =>
                      ('!', '网络连接失败，请检查网络后重试', Icons.wifi_off),
                    DioException() => (
                      '!',
                      '服务暂时不可用'
                          '（HTTP ${error.response?.statusCode ?? '错误'}）',
                      Icons.cloud_off
                    ),
                    _ => ('!', '查询失败，请稍后重试', Icons.error_outline),
                  };
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 40, color: const Color(0xFF114598)),
                  const SizedBox(height: 8),
                  Text(headline,
                      style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF114598))),
                  Text(message),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(() => _future = _repo()
                        .fetchOnline(
                            trainNum: widget.keyword, date: widget.date)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                color: const Color(0xFF114598),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(d.trainNum,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const Spacer(),
                        if (d.v1ComplementFailed)
                          const Tooltip(
                              message: '交路补全失败（不影响主数据）',
                              child: Icon(Icons.warning_amber_rounded,
                                  color: Colors.amberAccent)),
                      ]),
                      const SizedBox(height: 4),
                      Text('${d.bureauShortName} · ${d.car} · ${d.runner}',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('车厢图'),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CoachPicPage(
                        api: ref.read(railGoApiProvider),
                        trainNum: d.trainNum,
                        carModel: d.car),
                  )),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('线路点'),
                  onPressed: () => _showMapLine(d),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.icon(
                  onPressed: _added ? null : () => _addToTrips(d),
                  icon: Icon(_added ? Icons.check : Icons.add),
                  label: Text(_added ? '已加入' : '加入旅途'),
                )),
              ]),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final s in d.stops)
                      ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 52,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(s.arrive == '-' ? '--' : s.arrive,
                                  style: const TextStyle(
                                      fontSize: 12, fontFamily: 'DIN1451')),
                              Text(s.depart == '-' ? '--' : s.depart,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'DIN1451',
                                      color: Color(0xFF114598))),
                            ],
                          ),
                        ),
                        title: Text(s.station),
                        trailing: Text(
                            '${s.distance}${s.distance != '-' ? 'km' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.dataSource,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF114598),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMapLine(TrainDetail d) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(railGoApiProvider)
            .getMapLine(d.trainNum)
            .then((r) => r.data ?? <String, dynamic>{}),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 360, child: Center(child: CircularProgressIndicator()));
          }
          final raw = snap.data?['data'];
          if (raw is! Map) {
            return const SizedBox(
                height: 240, child: Center(child: Text('暂无线路点数据')));
          }
          final data = MapLineData.parseGCJ(Map<String, dynamic>.from(raw));
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${d.trainNum} 运行线路（WGS-84）',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                RouteLineMapView(data: data),
              ],
            ),
          );
        },
      ),
    );
  }
}
