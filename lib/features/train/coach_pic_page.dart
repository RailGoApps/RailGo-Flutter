// lib/features/train/coach_pic_page.dart
//
// 列车车厢图页（基线 pages/train/TrainPics.vue 移植——Phase 4 清单第 5 项）：
//   V2 /api/v2/getCoachPic?train= 官方车厢图 + tp 图床车型众包图双源。
library;

import 'package:flutter/material.dart';

import '../../core/network/railgo_api.dart';

class CoachPicPage extends StatefulWidget {
  const CoachPicPage({super.key, required this.api, required this.trainNum, this.carModel});
  final RailGoApi api;
  final String trainNum;

  /// 车型（如 CR400BF，"重联"后缀需先去除——基线 fetchImageSource 实证）
  final String? carModel;

  @override
  State<CoachPicPage> createState() => _CoachPicPageState();
}

class _CoachPicPageState extends State<CoachPicPage> {
  String? _officialUrl;
  String? _crowdUrl;
  String? _uploader;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 双源并发，任一失败静默（基线降级语义）
    final futures = <Future<void>>[
      () async {
        try {
          final r = await widget.api.getCoachPic(widget.trainNum);
          final d = r.data;
          if (d != null && d['success'] == true && d['data'] is Map) {
            final url = (d['data'] as Map)['image_url'] ?? (d['data'] as Map)['url'];
            if (mounted && url != null) setState(() => _officialUrl = url.toString());
          }
        } on Exception {
          // 静默降级
        }
      }(),
      () async {
        final model = widget.carModel?.replaceAll(' 重联', '');
        if (model == null || model.isEmpty) return;
        try {
          final r = await widget.api.carModelImage(model);
          final d = r.data;
          if (d != null && d['success'] == true && d['data'] is Map) {
            final m = d['data'] as Map;
            if (mounted) {
              setState(() {
                _crowdUrl = m['image_url']?.toString();
                _uploader = m['uploader_username']?.toString() ?? '匿名';
              });
            }
          }
        } on Exception {
          // 静默降级
        }
      }(),
    ];
    await Future.wait(futures);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.trainNum} 车厢图')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_officialUrl != null) _section('官方车厢图', _officialUrl!),
                if (_crowdUrl != null)
                  _section('车型图（tp 图床·上传者：$_uploader）', _crowdUrl!),
                if (_officialUrl == null && _crowdUrl == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无车厢图数据')),
                  ),
              ],
            ),
    );
  }

  Widget _section(String title, String url) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('图片加载失败')),
            ),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
          ),
        ],
      ),
    );
  }
}
