// lib/features/oobe/doc_page.dart
//
// Markdown 文档页（任务书 §4.6）：
//   /about /eula /privacy /permissions → assets/docs/*.md
//   容灾：flutter_markdown 加载失败 → 硬编码兜底文本 + 官网链接。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DocAssetPage extends StatelessWidget {
  const DocAssetPage(
      {super.key,
      required this.docAsset,
      required this.fallbackText,
      this.appBarTitle});

  /// 例 'assets/docs/eula.md'
  final String docAsset;

  /// 渲染失败时的硬编码兜底（任务书 §3.1：Markdown → 硬编码兜底文本 + 官网链接）
  final String fallbackText;
  final String? appBarTitle;

  static const Map<String, String> kRoutes = {
    '/about': 'assets/docs/about.md',
    '/eula': 'assets/docs/eula.md',
    '/privacy': 'assets/docs/privacy.md',
    '/permissions': 'assets/docs/permissions.md',
  };

  Future<String> _load(BuildContext context) async {
    try {
      return await DefaultAssetBundle.of(context).loadString(docAsset);
    } catch (_) {
      return fallbackText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle ?? docAsset.split('/').last)),
      body: FutureBuilder<String>(
        future: _load(context),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? fallbackText;
          return Markdown(data: data, selectable: true);
        },
      ),
    );
  }
}

/// 各文档兜底文本（保证极端情况下协议仍可读）
const kDocFallbacks = <String, String>{
  'assets/docs/about.md': '''
# RailGo

数据来源：RailGo (railgo.dev)
https://railgo.dev

文档加载失败，请访问官网获取完整内容。
''',
  'assets/docs/eula.md': '''
# 最终用户许可协议（兜底摘要）

- 本软件禁止欧盟成员国公民及位于欧盟境内的实体使用。
- 部分已去标识化数据可能传输至泛中华地区（主要为中国内地）处理。
- 数据由 RailGo (railgo.dev) 提供，不得用于商业用途。
- 完整协议请访问 https://railgo.dev
''',
  'assets/docs/privacy.md': '''
# 隐私政策（兜底摘要）

敏感数据（证件/生物特征）仅存储于设备本地，使用国密 SM4 加密，绝不上传。
完整政策请访问 https://railgo.dev
''',
  'assets/docs/permissions.md': '''
# 权限说明（兜底摘要）

所有权限均为可选；拒绝不影响核心查询功能。逐项说明请访问 https://railgo.dev
''',
};
