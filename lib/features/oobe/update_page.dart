// lib/features/oobe/update_page.dart
//
// 更新管理（基线 pages/update/db.vue 移植——Phase 4 清单第 3 项）：
//   软件本体（Android only）+ 离线数据库双卡片；版本比对 + 下载跳转。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/network/railgo_api.dart';
import 'version_compare.dart';

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
      // 实测（2026-09-25）网关返回：{"latest_db":61,"db":"20260920",
      // "latest_pack":30,"pack":"2.0.6 Build 20006"}——旧代码读
      // appVersion/dbVersion（不存在的字段）导致永远显示"已是最新"。
      // 兼容口径：app 用 appVersion ?? pack；db 用 dbVersion ?? latest_db。
      UpdateCheckResult? appResult;
      if (widget.isAndroid) {
        final pack = await widget.api.androidPackUrl();
        final latestApp =
            (data?['appVersion'] ?? data?['pack'] ?? '').toString();
        appResult = UpdateCheckResult(
          latest: latestApp,
          current: kAppVersionText,
          hasUpdate: isNewerVersion(latestApp, kAppVersionText),
          downloadUrl: (pack.data?['data'] is Map)
              ? pack.data!['data']['url'] as String?
              : null,
        );
      }
      final dbUrl = await widget.api.offlineDbUrl();
      final latestDb =
          (data?['dbVersion'] ?? data?['latest_db'] ?? '').toString();
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
    } on DioException catch (e) {
      // 审计 U-04：异常分类为人话文案，不外泄内部域名/堆栈细节
      setState(() {
        _error = switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            '网络连接超时，请检查网络后重试',
          DioExceptionType.connectionError => '网络连接失败，请检查网络后重试',
          _ => '更新服务暂时不可用，请稍后重试',
        };
      });
    } on Exception {
      setState(() => _error = '检查更新失败，请稍后重试');
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
                  // 审计 U-04：死按钮 → 校验 https 后复制下载地址
                  // （url_launcher 尚未引入，浏览器打开由用户完成）
                  onPressed: r.downloadUrl == null
                      ? null
                      : () async {
                          final url = r.downloadUrl!;
                          final uri = Uri.tryParse(url);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.scheme != 'https') {
                            _snack('下载地址无效，请联系开发者');
                            return;
                          }
                          await Clipboard.setData(ClipboardData(text: url));
                          if (!mounted) return;
                          _snack('下载地址已复制，请在浏览器打开');
                        },
                  child: const Text('立即更新'),
                ),
              ),
            if (r.hasUpdate && r.downloadUrl == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '暂无下载地址（新版本可能尚未发布）',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
