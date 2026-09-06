// lib/features/certificate/certificates_page.dart
//
// 证件管理页（任务书 §4.3 UI：默认"已加密"，点击触发 Passkey → 明文；新增/编辑需验证）
library;

import 'package:flutter/material.dart';

import '../../core/security/auth_gate.dart';
import 'certificate_repository.dart';

class CertificatesPage extends StatelessWidget {
  const CertificatesPage({super.key, required this.repository, this.gate});
  final CertificateRepository repository;

  /// 可选 PIN 门禁（生物识别失败后的回退通道）
  final LocalAuthGate? gate;

  Future<bool> _pinFallback(BuildContext context) async {
    final g = gate;
    if (g == null) return false;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('请输入 6 位数字 PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('验证')),
        ],
      ),
    );
    if (ok != true) return false;
    final r = await g.verifyPin(controller.text);
    return r.passed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('证件管理')),
      body: FutureBuilder<List<Certificate>>(
        future: () async {
          try {
            return await repository.unlockAll();
          } on GateDeniedException {
            // 生物识别未过 → PIN 回退（红队：禁止无验证直接放行）
            if (await _pinFallback(context)) {
              return await repository.unlockAll();
            }
            rethrow;
          }
        }(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('🔒 验证未通过或数据损坏：${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          final certs = snap.data ?? const <Certificate>[];
          if (certs.isEmpty) {
            return const Center(child: Text('暂无证件，点击右下角添加'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: certs.length,
            itemBuilder: (context, i) {
              final c = certs[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text('${c.name}（${_typeLabel(c.type)}）'),
                  subtitle: Text(_mask(c.number),
                      style: const TextStyle(letterSpacing: 2)),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddSheet(context),
      ),
    );
  }

  String _mask(String number) {
    if (number.length <= 6) return '******';
    return number.substring(0, 3) +
        ' * ' * (number.length - 6) +
        number.substring(number.length - 3);
  }

  String _typeLabel(CertType t) => switch (t) {
        CertType.residentId => '身份证',
        CertType.passport => '护照',
        CertType.hkmTravelPermit => '港澳通行证',
        CertType.twTravelPermit => '台胞证',
        CertType.other => '其他',
      };

  Future<void> _showAddSheet(BuildContext context) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final birth = TextEditingController();
    var type = CertType.residentId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<CertType>(
              value: type,
              isExpanded: true,
              items: [
                for (final t in CertType.values)
                  DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
              ],
              onChanged: (v) => setSheet(() => type = v ?? type),
            ),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '姓名（必填）')),
            TextField(
                controller: number,
                decoration: const InputDecoration(labelText: '证件号码（必填）')),
            TextField(
                controller: birth,
                decoration:
                    const InputDecoration(labelText: '出生日期 yyyymmdd（必填）')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存（将验证并 SM4 加密）'),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) {
      if (name.text.isEmpty ||
          number.text.isEmpty ||
          !RegExp(r'^\d{8}$').hasMatch(birth.text)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('必填字段不完整')));
        }
        return;
      }
      try {
        await repository.save(Certificate(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: type,
          number: number.text,
          name: name.text,
          birthDate: birth.text,
        ));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已加密保存')));
        }
      } on GateDeniedException {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('🔒 验证未通过，未保存')));
        }
      }
    }
  }
}
