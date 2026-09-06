// lib/features/oobe/update_page.dart
//
// 更新管理（基线 pages/update/db.vue 移植——Phase 4 清单第 3 项）：
//   软件本体（Android only）+ 离线数据库双卡片；版本比对 + 下载跳转。
library;

import 'package:flutter/material.dart';

import '../../core/network/railgo_api.dart';

const String kAppVersionText = '3.0.0 Build 30000';

class UpdateCheckResult {
  const UpdateCheckResult(
      {required this.latest,
      required this.current,
      required this.hasUpdate,
      this.downloadUrl});
  final String latest;
  final String current;
  final bool hasUpdate;
  final String? downloadUrl;
}

class UpdatePage extends StatefulWidget {
  const UpdatePage(
      {super.key,
      required this.api,
      this.currentDbVersion = '未下载',
      this.isAndroid = true});
  final RailGoApi api;
  final String currentDbVersion;
  final bool isAndroid;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  UpdateCheckResult? _appResult;
  UpdateCheckResult? _dbResult;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.api.updateInfo();
      final data = info.data;
      UpdateCheckResult? appResult;
      if (widget.isAndroid) {
        final pack = await widget.api.androidPackUrl();
        final latestApp = (data?['appVersion'] ?? '').toString();
        appResult = UpdateCheckResult(
          latest: latestApp,
          current: kAppVersionText,
          hasUpdate: latestApp.isNotEmpty && latestApp != kAppVersionText,
          downloadUrl: (pack.data?['data'] is Map)
              ? pack.data!['data']['url'] as String?
              : null,
        );
      }
      final dbUrl = await widget.api.offlineDbUrl();
      final latestDb = (data?['dbVersion'] ?? '').toString();
      final dbResult = UpdateCheckResult(
        latest: latestDb,
        current: widget.currentDbVersion,
        hasUpdate: latestDb.isNotEmpty && latestDb != widget.currentDbVersion,
        downloadUrl: (dbUrl.data?['data'] is Map)
            ? dbUrl.data!['data']['url'] as String?
            : null,
      );
      setState(() {
        _appResult = appResult;
        _dbResult = dbResult;
      });
    } on Exception catch (e) {
      setState(() => _error = '检查更新失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isAndroid) ...[
            const Text('软件本体', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _card(_appResult),
            const SizedBox(height: 20),
          ],
          const Text('数据库', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _card(_dbResult),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _card(UpdateCheckResult? r) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (r == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.hasUpdate ? '发现新版本' : '已是最新',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: r.hasUpdate
                            ? const Color(0xFF114598)
                            : Colors.green.shade700,
                      )),
                ),
                Icon(
                    r.hasUpdate
                        ? Icons.download_rounded
                        : Icons.check_circle_outline,
                    color: r.hasUpdate
                        ? const Color(0xFF114598)
                        : Colors.green.shade700),
              ],
            ),
            const Divider(height: 20),
            Text('当前版本：${r.current}'),
            if (r.hasUpdate) Text('最新版本：${r.latest}'),
            if (r.hasUpdate)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(
                  onPressed: () {}, // 下载交给系统集成（url_launcher/webview 由壳层注入）
                  child: const Text('立即更新'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
