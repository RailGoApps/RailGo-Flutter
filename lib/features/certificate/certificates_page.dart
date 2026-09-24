// lib/features/certificate/certificates_page.dart
//
// 证件管理页 v2：
//   会话门禁 —— 进入必须授权面容/指纹（失败→PIN 回退），会话内读写删导出
//               共享授权；离开页面或手动上锁立即失效。
//   一人多证 —— 按"姓名+出生日期"分组展示，同号不同人告警。
//   号码识读 —— 身份证/居住证/永居证号码自动提取出生日期、性别、校验位。
//   MRZ 识读 —— ICAO 9303 TD1/TD2/TD3，校验位逐项验证后入库。
//   导出导入 —— 口令加密信封（TEE 密钥不可导出 → 跨设备用口令迁移）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/auth_gate.dart';
import 'certificate_catalog.dart';
import 'certificate_repository.dart';
import 'certificate_types.dart';
import 'id_number.dart';
import 'mrz.dart';

class CertificatesPage extends StatefulWidget {
  const CertificatesPage({super.key, required this.repository, this.gate});

  final CertificateRepository repository;

  /// 通行密钥门禁（面容/指纹 + PIN 回退）；null 时仍由仓储内部强制门禁
  final LocalAuthGate? gate;

  @override
  State<CertificatesPage> createState() => _CertificatesPageState();
}

class _CertificatesPageState extends State<CertificatesPage> {
  SessionAuthGate? _session;
  late final CertificateRepository _repo;

  bool _busy = true;
  String? _error;
  List<Certificate> _certs = const <Certificate>[];

  @override
  void initState() {
    super.initState();
    final g = widget.gate;
    if (g != null) {
      _session = SessionAuthGate(g);
      _repo = widget.repository.withGate(_session!);
    } else {
      _repo = widget.repository;
    }
    _reload();
  }

  @override
  void dispose() {
    _session?.lock(); // 离开页面即上锁
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var certs = const <Certificate>[];
    String? error;
    try {
      certs = await _repo.unlockAll();
    } on GateDeniedException {
      var ok = false;
      if (mounted) ok = await _pinFallback();
      if (ok) {
        try {
          certs = await _repo.unlockAll();
        } on Exception catch (e) {
          error = '读取失败：$e';
        }
      } else {
        error = '通行密钥未授权，无法访问证件库';
      }
    } on Exception catch (e) {
      error = '读取失败：$e';
    }
    if (!mounted) return;
    setState(() {
      _certs = certs;
      _error = error;
      _busy = false;
    });
  }

  /// 生物识别失败后的 PIN 回退（未设置 PIN 则保持拒绝——红队规则）
  Future<bool> _pinFallback() async {
    final s = _session;
    if (s == null || !s.hasPin) return false;
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('验证'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final r = await s.verifyPin(controller.text);
    return r.passed;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupCertificatesByPerson(_certs);
    final dups = duplicateCertificateNumberWarnings(_certs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('证件管理'),
        actions: [
          IconButton(
            tooltip: _session?.unlocked == true ? '立即上锁' : '已上锁',
            icon: Icon(
              _session?.unlocked == true
                  ? Icons.lock_open_outlined
                  : Icons.lock_outline,
            ),
            onPressed: _session == null
                ? null
                : () {
                    _session!.lock();
                    _reload();
                  },
          ),
          IconButton(
            tooltip: '通行密钥',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => _showPasskeySheet(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') {
                _showExportSheet(context);
              } else if (v == 'import') {
                _showImportSheet(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: Text('导出加密备份'),
              ),
              PopupMenuItem(
                value: 'import',
                child: Text('导入备份'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(groups, dups),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(List<PersonGroup> groups, List<String> dups) {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🔒 $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (groups.isEmpty) {
      return const Center(child: Text('暂无证件，点击右下角添加'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        for (final w in [...dups, ..._expiryWarnings(_certs)])
          Card(
            color: const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(w, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        for (final g in groups) _personCard(g),
      ],
    );
  }

  Widget _personCard(PersonGroup g) {
    final birth = g.birthDate;
    final age = certAgeAt(birth, DateTime.now());
    final attention = g.certificates
        .where((c) =>
            certExpiryInfo(c.expiryDate).status !=
            CertExpiryStatus.valid)
        .length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF114598),
              foregroundColor: Colors.white,
              child: Text(g.name.isEmpty ? '?' : g.name.substring(0, 1)),
            ),
            title: Text(g.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (birth != null) '生日 ${_fmtYmd(birth)}',
              if (age != null) '$age 岁',
              '${g.certCount} 本证件',
              if (attention > 0) '⚠ $attention 本临期/过期',
            ].join(' · ')),
          ),
          for (final c in g.certificates) _certTile(c),
        ],
      ),
    );
  }

  Widget _certTile(Certificate c) {
    final insight = analyzeCertNumber(c.typeCode, c.number);
    final age = certAgeAt(c.birthDate, DateTime.now());
    final expiry = certExpiryInfo(c.expiryDate);
    final usage = certUsage(c.typeCode);
    final limit =
        certLimitationHint(c.typeCode, nationalityCode: c.nationalityCode);
    final days = expiry.daysRemaining ?? 0;
    final expiryText = c.expiryDate == null
        ? ''
        : switch (expiry.status) {
            CertExpiryStatus.expired => '已过期${days < 0 ? ' ${-days} 天' : ''}',
            CertExpiryStatus.expiringSoon =>
              '有效期至 ${_fmtYmd(c.expiryDate!)}（剩 $days 天）',
            _ => '有效期至 ${_fmtYmd(c.expiryDate!)}',
          };
    final sub = [
      if (c.birthDate != null) _fmtYmd(c.birthDate!),
      if (age != null) '$age 岁',
      if (c.sex != null) c.sex!,
      if (c.nationality != null) c.nationality!,
      if (expiryText.isNotEmpty) expiryText,
    ].join(' · ');
    return ListTile(
      dense: true,
      leading: Icon(
        c.source == CertSource.mrz
            ? Icons.document_scanner_outlined
            : Icons.badge_outlined,
        color: switch (expiry.status) {
          CertExpiryStatus.expired => Colors.red,
          CertExpiryStatus.expiringSoon => const Color(0xFFE65100),
          _ => null,
        },
      ),
      title: Text(
        '${certShortName(c.typeCode)} · ${_mask(c.number)}'
        '${c.source == CertSource.mrz ? '  [MRZ]' : ''}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sub,
              style: TextStyle(
                fontSize: 12,
                color: switch (expiry.status) {
                  CertExpiryStatus.expired => Colors.red,
                  CertExpiryStatus.expiringSoon =>
                    const Color(0xFFE65100),
                  _ => null,
                },
              )),
          if (usage != CertUsage.regular)
            Text(
              '${certUsageLabel(usage)} · ${limit ?? '建议用后删除'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),
            ),
          if (insight.checksumOk == false)
            const Text('号码校验位不符',
                style: TextStyle(fontSize: 11, color: Colors.red)),
        ],
      ),
      trailing: IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(c),
      ),
    );
  }

  Future<void> _delete(Certificate c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除证件'),
        content: Text(
            '确定删除 ${c.name} 的 '
            '${certShortName(c.typeCode)}（${_mask(c.number)}）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteSecure(c.id);
      unawaited(_reload());
    } on GateDeniedException {
      _snack('🔒 通行密钥未授权，未删除');
    }
  }

  // ─────────────── 新增（手输 + 号码识读） ───────────────

  Future<void> _showAddSheet(BuildContext context) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final birth = TextEditingController();
    final expiry = TextEditingController();
    var type = 'ED';
    var showAll = false;
    var chineseNational = true; // BS 护照报失证明的国籍口径
    final errors = <String>[];

    final ok = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          List<String> codes() => (showAll ? kCertCodes : kPrimaryCertCodes)
              .where(certStorable)
              .toList(growable: false);
          final usage = certUsage(type);
          final natCode = chineseNational ? 'CHN' : 'ZZ';
          final hint = certLimitationHint(type, nationalityCode: natCode);
          final expiryPolicy =
              certExpiryPolicy(type, nationalityCode: natCode);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: codes().contains(type) ? type : codes().first,
                        isExpanded: true,
                        items: [
                          for (final c in codes())
                            DropdownMenuItem(
                              value: c,
                              child: Text(certDisplayName(c)),
                            ),
                        ],
                        onChanged: (v) => setSheet(() {
                          type = v ?? type;
                          _syncBirth(
                              analyzeCertNumber(type, number.text), birth);
                        }),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setSheet(() {
                        showAll = !showAll;
                        if (!codes().contains(type)) type = codes().first;
                      }),
                      child: Text(showAll ? '常用类型' : '全部类型'),
                    ),
                  ],
                ),
                if (usage != CertUsage.regular)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${certUsageLabel(usage)} · ${hint ?? '建议用后删除'}',
                      style: const TextStyle(
                          color: Color(0xFFE65100), fontSize: 12),
                    ),
                  ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '姓名（必填）'),
                ),
                TextField(
                  controller: number,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setSheet(
                    () =>
                        _syncBirth(analyzeCertNumber(type, v), birth),
                  ),
                  decoration: InputDecoration(
                    labelText: '证件号码（必填）',
                    helperText: certNumberHint(type),
                  ),
                ),
                if (type == 'BS')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('中国籍'),
                    subtitle: Text(chineseNational
                        ? '无使用天数限制'
                        : '非中国籍：有效期 30 天，需填写有效期'),
                    value: chineseNational,
                    onChanged: (v) => setSheet(() => chineseNational = v),
                  ),
                TextField(
                  controller: birth,
                  enabled: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '出生日期 yyyymmdd',
                    helperText: '身份证/居住证/永居证可由号码自动识读',
                  ),
                ),
                TextField(
                  controller: expiry,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: expiryPolicy == CertExpiryPolicy.required
                        ? '有效期至 yyyymmdd（必填）'
                        : '有效期至 yyyymmdd',
                    helperText: switch (expiryPolicy) {
                      CertExpiryPolicy.required =>
                        '短期证件：不填有效期无法判断可用性',
                      CertExpiryPolicy.recommended =>
                        '该证件有固定有效期，建议填写以获得到期提醒',
                      CertExpiryPolicy.optional =>
                        '长期证件可不填；临时/一次性证件建议填写',
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _insightPanel(analyzeCertNumber(type, number.text)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('改用 MRZ 机读区识读'),
                  onPressed: () => Navigator.pop(context, 'mrz'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('保存（将验证并 SM4 加密）'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok == 'mrz') {
      unawaited(_showMrzSheet(context));
      return;
    }
    if (ok != true) return;

    // 校验（弹层关闭后统一反馈）
    final ins = analyzeCertNumber(type, number.text);
    final trimmedName = name.text.trim();
    final trimmedNumber =
        number.text.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (trimmedName.isEmpty || trimmedNumber.isEmpty) {
      errors.add('姓名与证件号码必填');
    }
    if (certNumberEncodesBirth(type) && ins.birthDate == null) {
      errors.add('无法从号码识读出生日期：${ins.warning ?? '格式不符'}');
    }
    if (ins.checksumOk == false) {
      errors.add('号码校验位不符，请核对');
    }
    if (birth.text.trim().isNotEmpty &&
        !RegExp(r'^\d{8}$').hasMatch(birth.text.trim())) {
      errors.add('出生日期应为 8 位 yyyymmdd');
    }
    final birthFinal = birth.text.trim().isNotEmpty
        ? birth.text.trim()
        : ins.birthDate;
    final maxAge = certMaxAgeYears(type);
    if (maxAge != null && birthFinal != null) {
      final age = certAgeAt(birthFinal, DateTime.now());
      if (age != null && age > maxAge) {
        errors.add('该证件类型仅限 $maxAge 周岁以下');
      }
    }
    final expiryFinal = expiry.text.trim();
    if (expiryFinal.isNotEmpty &&
        !RegExp(r'^\d{8}$').hasMatch(expiryFinal)) {
      errors.add('有效期应为 8 位 yyyymmdd');
    }
    final maxDays = certMaxValidityDays(
      type,
      nationalityCode: chineseNational ? 'CHN' : 'ZZ',
    );
    if (maxDays != null) {
      if (expiryFinal.isEmpty) {
        errors.add('非中国籍 $maxDays 天限制：必须填写有效期');
      } else {
        final limit = _ymd(DateTime.now().add(Duration(days: maxDays)));
        if (expiryFinal.compareTo(limit) > 0) {
          errors.add('非中国籍有效期上限为 $maxDays 天（$limit）');
        }
      }
    } else if (certExpiryPolicy(
              type,
              nationalityCode: chineseNational ? 'CHN' : 'ZZ',
            ) ==
            CertExpiryPolicy.required &&
        expiryFinal.isEmpty) {
      errors.add('该证件类型必须填写有效期（yyyymmdd）');
    }
    if (errors.isNotEmpty) {
      _snack(errors.join('；'));
      return;
    }

    try {
      await _repo.save(Certificate(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        typeCode: type,
        number: trimmedNumber,
        name: trimmedName,
        birthDate: birthFinal,
        sex: ins.gender == CertGender.unknown
            ? null
            : certGenderLabel(ins.gender),
        nationalityCode: type == 'BS' ? (chineseNational ? 'CHN' : 'ZZ') : null,
        nationality:
            type == 'BS' ? (chineseNational ? '中国/China' : '非中国籍') : null,
        expiryDate: expiryFinal.isEmpty ? null : expiryFinal,
      ));
      _snack('已加密保存');
      unawaited(_reload());
    } on GateDeniedException {
      _snack('🔒 通行密钥未授权，未保存');
    }
  }

  /// 号码识读结果自动回填出生日期（用户手改后不再覆盖）
  void _syncBirth(IdNumberInsight ins, TextEditingController birth) {
    if (ins.birthDate != null && birth.text.isEmpty) {
      birth.text = ins.birthDate!;
    }
  }

  Widget _insightPanel(IdNumberInsight ins) {
    if (!ins.hasData) {
      return const SizedBox.shrink();
    }
    final age = certAgeAt(ins.birthDate, DateTime.now());
    final chips = <Widget>[
      if (ins.formattedBirth != null)
        Chip(label: Text('生日 ${ins.formattedBirth}')),
      if (age != null) Chip(label: Text('$age 岁')),
      if (ins.gender != CertGender.unknown)
        Chip(label: Text(certGenderLabel(ins.gender))),
      if (ins.regionCode != null)
        Chip(label: Text(kRegionNames[ins.regionCode!] ?? ins.regionCode!)),
      if (ins.checksumOk != null)
        Chip(
          label: Text(ins.checksumOk! ? '校验位 ✓' : '校验位 ✗'),
          backgroundColor:
              ins.checksumOk! ? null : const Color(0xFFFFEBEE),
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...chips,
        if (ins.warning != null)
          Text(ins.warning!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
    );
  }

  // ─────────────── MRZ 机读区识读 ───────────────

  Future<void> _showMrzSheet(BuildContext context) async {
    final input = TextEditingController();
    final name = TextEditingController();
    MrzResult? parsed;
    String? parseError;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget preview() {
            final r = parsed;
            if (r == null) return const SizedBox.shrink();
            final age = certAgeAt(r.birthDate, DateTime.now());
            Widget check(String label, bool ok) => Chip(
                  label: Text('$label ${ok ? '✓' : '✗'}'),
                  backgroundColor:
                      ok ? null : const Color(0xFFFFEBEE),
                );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${mrzFormatLabel(r.format)} · '
                        '${certDisplayName(r.certTypeCode)}'),
                    Text('号码：${r.documentNumber} · '
                        '${r.nationalityName}'),
                    Text('出生：${_fmtYmd(r.birthDate)} · '
                        '${certGenderLabel(r.sex)}'
                        '${age != null ? ' · $age 岁' : ''}'),
                    Text('有效期至：${_fmtYmd(r.expiryDate)}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        check('号码校验', r.docNumberCheckOk),
                        check('生日校验', r.birthCheckOk),
                        check('有效期校验', r.expiryCheckOk),
                        check('综合校验', r.compositeCheckOk),
                        if (r.format == MrzFormat.td3)
                          check('个人号校验', r.personalNumberCheckOk),
                      ],
                    ),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '姓名（可改为中文名以关联同一出行人）',
                      ),
                    ),
                    if (!r.allChecksOk)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '部分校验位不符：请核对机读区是否完整抄录',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('MRZ 机读区识读（ICAO 9303）',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  '支持 TD1（3×30）/TD2（2×36）/TD3（2×44）；'
                  '可整段粘贴，扫描枪单行连打也可自动分行',
                  style: TextStyle(fontSize: 12),
                ),
                TextField(
                  controller: input,
                  minLines: 3,
                  maxLines: 5,
                  style: const TextStyle(
                      fontFamily: 'DIN1451', letterSpacing: 1.2),
                  decoration: const InputDecoration(hintText: 'P<CHN...'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    try {
                      final r = parseMrz(input.text);
                      setSheet(() {
                        parsed = r;
                        parseError = null;
                        name.text = r.fullName;
                      });
                    } on FormatException catch (e) {
                      setSheet(() {
                        parsed = null;
                        parseError = e.message;
                      });
                    }
                  },
                  child: const Text('解析'),
                ),
                if (parseError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(parseError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                preview(),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: parsed == null
                      ? null
                      : () => Navigator.pop(context, 'save'),
                  child: const Text('存入证件库（SM4 加密）'),
                ),
              ],
            ),
          );
        },
      ),
    );

    final r = parsed;
    if (action != 'save' || r == null) return;

    var confirmed = r.allChecksOk;
    if (!confirmed) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('校验位不符'),
              content: const Text('机读区可能抄录有误，仍要保存吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('再检查'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仍要保存'),
                ),
              ],
            ),
          ) ==
          true;
    }
    if (!confirmed) return;

    final finalName =
        name.text.trim().isEmpty ? r.fullName : name.text.trim();
    try {
      await _repo.save(Certificate(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        typeCode: r.certTypeCode,
        number: r.documentNumber,
        name: finalName,
        birthDate: r.birthDate,
        sex:
            r.sex == CertGender.unknown ? null : certGenderLabel(r.sex),
        nationalityCode: r.nationalityCode,
        nationality: r.nationalityName,
        expiryDate: r.expiryDate,
        source: CertSource.mrz,
      ));
      _snack('已加密保存（MRZ）');
      unawaited(_reload());
    } on GateDeniedException {
      _snack('🔒 通行密钥未授权，未保存');
    }
  }

  // ─────────────── 通行密钥管理 ───────────────

  Future<void> _showPasskeySheet(BuildContext context) async {
    final gate = widget.gate;
    final pin = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('通行密钥',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: gate?.biometricKinds() ?? Future.value(const <String>[]),
              builder: (context, snap) {
                final kinds = snap.data ?? const <String>[];
                return ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('生物识别（系统级）'),
                  subtitle: Text(kinds.isEmpty
                      ? '未登记或不可用'
                      : kinds.join('、')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(gate?.hasPin == true ? 'PIN 已设置' : 'PIN 未设置'),
              subtitle: const Text('生物识别失败/不可用时的回退通道'),
            ),
            if (gate != null) ...[
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '设置/更换 6 位数字 PIN',
                  counterText: '',
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await gate.setupPin(pin.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'PIN 已更新' : 'PIN 必须为 6 位数字')));
                    Navigator.pop(context);
                  }
                },
                child: const Text('保存 PIN'),
              ),
              TextButton(
                onPressed: () async {
                  await gate.clearPin();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('清除 PIN'),
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '面容/指纹数据仅存在于系统安全区域（TEE/安全隔区），'
                'RailGo 永不采集生物特征，只收到"通过/未通过"结果。',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── 导出 / 导入 ───────────────

  Future<void> _showExportSheet(BuildContext context) async {
    final pass = TextEditingController();
    String? result;
    String? error;
    await showModalBottomSheet<void>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('导出加密备份',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'TEE 设备密钥不可导出：备份用你设置的口令重新加密（SM4），'
                '跨设备迁移时凭口令恢复；口令不设找回，请牢记。',
                style: TextStyle(fontSize: 12),
              ),
              TextField(
                controller: pass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '导出口令（≥8 位）'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  try {
                    final r = await _repo.exportEncrypted(pass.text);
                    setSheet(() {
                      result = r;
                      error = null;
                    });
                  } on GateDeniedException {
                    setSheet(() => error = '通行密钥未授权');
                  } on FormatException catch (e) {
                    setSheet(() => error = e.message);
                  }
                },
                child: const Text('生成密文备份'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              if (result != null) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('复制密文'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result!));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制，可安全粘贴传输')));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showImportSheet(BuildContext context) async {
    final pass = TextEditingController();
    final payload = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('导入备份',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              TextField(
                controller: pass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '导出口令'),
              ),
              TextField(
                controller: payload,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '粘贴备份密文',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  try {
                    final r = await _repo.importEncrypted(
                        pass.text, payload.text.trim());
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    _snack('导入完成：新增 ${r.added} 本，'
                        '去重跳过 ${r.skipped} 本');
                    unawaited(_reload());
                  } on GateDeniedException {
                    setSheet(() => error = '通行密钥未授权');
                  } on FormatException catch (e) {
                    setSheet(() => error = '口令错误或备份损坏：${e.message}');
                  }
                },
                child: const Text('解密并导入'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── 小工具 ───────────────

  String _mask(String number) {
    if (number.length <= 6) return '******';
    return number.substring(0, 3) + ' * ' + number.substring(number.length - 3);
  }

  String _fmtYmd(String ymd) => ymd.length == 8
      ? '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6, 8)}'
      : ymd;

  String _ymd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// 库级到期提醒（已过期 → 不可用；30 天内 → 临期）
  List<String> _expiryWarnings(List<Certificate> certs) {
    final out = <String>[];
    for (final c in certs) {
      final e = certExpiryInfo(c.expiryDate);
      if (e.status == CertExpiryStatus.expired) {
        out.add('${c.name} 的 ${certShortName(c.typeCode)} 已过期，'
            '不可用于实名购票');
      } else if (e.status == CertExpiryStatus.expiringSoon) {
        out.add('${c.name} 的 ${certShortName(c.typeCode)} 将于 '
            '${_fmtYmd(c.expiryDate!)} 到期（剩 ${e.daysRemaining} 天）');
      }
    }
    return out;
  }
}
