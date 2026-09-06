// lib/features/home/home_page.dart
//
// 首页外壳：三 Tab（旅途 / 查询 / 设置）+ 三端自适应底栏（MD3E 浮动底栏含 FAB）。
// 行程板每分钟刷新（时钟驱动状态机，无网络依赖）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/key_service.dart';
import '../../core/storage/settings_store.dart';
import '../../main.dart';
import '../oobe/eggs.dart';
import '../../widgets/platform_adapter.dart';
import '../../widgets/train_keyboard.dart';
import '../certificate/certificate_repository.dart';
import '../certificate/certificates_page.dart';
import '../train/train_result_page.dart';
import '../trip/trip_store.dart';
import '../trip/trip_state_machine.dart';

final tripRepoProvider = Provider<TripRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  final settings = ref.watch(settingsProvider);
  return TripRepository(
    storage: PrefsTripStorage(prefs),
    clock: ref.watch(clockProvider),
    maxTransferHours: settings.maxTransferHours,
  );
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tab = 0;
  String _keyboardValue = '';
  Timer? _ticker;
  int _versionTaps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _tab == 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flavor = inferFlavor(Theme.of(context).platform);
    final items = [
      AdaptiveNavItem(
          label: l10n.tabTrips,
          icon: Icons.route_outlined,
          selectedIcon: Icons.route,
          onTap: () => setState(() => _tab = 0)),
      AdaptiveNavItem(
          label: l10n.tabQuery,
          icon: Icons.search_outlined,
          selectedIcon: Icons.search,
          onTap: () => setState(() => _tab = 1)),
      AdaptiveNavItem(
          label: l10n.tabSettings,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          onTap: () => setState(() => _tab = 2)),
    ];
    return Scaffold(
      body: switch (_tab) {
        0 => const _TripBoard(),
        1 => _buildQueryTab(context),
        _ => _buildSettingsTab(context),
      },
      bottomNavigationBar: AdaptiveBottomNav(
        flavor: flavor,
        items: items,
        selectedIndex: _tab,
        fabIcon: Icons.train_outlined,
        onFab: () => setState(() => _tab = 1),
      ),
    );
  }

  Widget _buildQueryTab(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_keyboardValue.isEmpty ? '输入车次号' : _keyboardValue,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          TrainKeyboard(
            value: _keyboardValue,
            onChanged: (v) => setState(() => _keyboardValue = v),
            onConfirm: () {
              if (_keyboardValue.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainResultPage(keyword: _keyboardValue),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.docAbout),
          subtitle: GestureDetector(
            onTap: () {
              // 彩蛋触发：版本号连点（对齐原 about.vue Logo 连点语义）
              setState(() => _versionTaps++);
              if (_versionTaps >= 5) {
                _versionTaps = 0;
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AboutEggRoute()));
              }
            },
            child: const Text('3.0.0'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/about'),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.docEula),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/eula'),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.docPrivacy),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/privacy'),
        ),
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: Text(l10n.docPermissions),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/permissions'),
        ),
        ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('更新管理'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/update'),
        ),
        ListTile(
          leading: const Icon(Icons.speed_outlined),
          title: const Text('实时测速'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/speed'),
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('证件管理（SM4 加密）'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final prefs = ref.read(sharedPrefsProvider);
            final gate = LocalAuthGate(prefs: prefs);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CertificatesPage(
                  gate: gate,
                  repository: CertificateRepository(
                    gate: gate,
                    keySource: SecureStorageKeyService(),
                    storage: PrefsCertificateStorage(prefs),
                  ),
                ),
              ),
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.cloud_outlined),
          title: Text(settings.mode == AppMode.network ? '优先在线' : '优先离线'),
          value: settings.mode == AppMode.network,
          onChanged: (v) async {
            await settings.setMode(v ? AppMode.network : AppMode.local);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('最大换乘时间'),
          subtitle: Slider(
            value: settings.maxTransferHours.toDouble(),
            min: 1,
            max: 24,
            divisions: 23,
            label: '${settings.maxTransferHours} h',
            onChanged: (v) async {
              await settings.setMaxTransferHours(v.round());
              setState(() {});
            },
          ),
          trailing: Text('${settings.maxTransferHours}h'),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.dataSource,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF114598), fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class AboutEggRoute extends StatelessWidget {
  const AboutEggRoute({super.key});

  @override
  Widget build(BuildContext context) => const AboutEggPage();
}

class _TripBoard extends ConsumerWidget {
  const _TripBoard();

  String _phaseLabel(AppLocalizations l10n, TripPhase phase) => switch (phase) {
        TripPhase.idle => l10n.stIdle,
        TripPhase.departingSoon => l10n.stDepartingSoon,
        TripPhase.nextStation => l10n.stNextStation,
        TripPhase.arrivingSoon => l10n.stArrivingSoon,
        TripPhase.stopped => l10n.stStopped,
        TripPhase.finished => l10n.stFinished,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(tripRepoProvider);
    return FutureBuilder<List<TripWithStatus>>(
      future: repo.loadTripBoard(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final board = snap.data ?? const <TripWithStatus>[];
        if (board.isEmpty) {
          return Center(
              child: Text(l10n.tripEmpty, textAlign: TextAlign.center));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: board.length,
          itemBuilder: (context, i) {
            final item = board[i];
            final warn = item.transferToNext?.warning;
            final msg = item.transferToNext?.message;
            return Card(
              child: ListTile(
                leading: SizedBox(
                  width: 64,
                  child: Center(
                    child: Text(item.trip.trainNum,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF114598))),
                  ),
                ),
                title: Text(
                    '${item.trip.stops.first.station} → ${item.trip.stops.last.station}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_phaseLabel(l10n, item.status.phase)),
                    if (warn != null)
                      Text(warn,
                          style: const TextStyle(
                              color: Color(0xFFB22222), fontSize: 12)),
                    if (msg != null)
                      Text(msg,
                          style: const TextStyle(
                              color: Color(0xFF459811), fontSize: 12)),
                  ],
                ),
                trailing: Text(item.trip.dateYmd,
                    style: const TextStyle(fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
