// lib/main.dart
//
// RailGo 铁路行 · Flutter 重构版入口
// 三端自适应（iOS Cupertino / Android MD3E / HarmonyOS ArkUI），5 语言，Asia/Shanghai 时区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n/app_localizations.dart';
import 'core/network/api_client.dart';
import 'core/network/railgo_api.dart';
import 'core/network/rate_limiter.dart';
import 'core/security/auth_gate.dart';
import 'core/security/key_service.dart';
import 'core/storage/settings_store.dart';
import 'core/utils/clock.dart';
import 'features/certificate/certificate_repository.dart';
import 'features/certificate/certificates_page.dart';
import 'features/home/home_page.dart';
import 'features/sensor/speed_page.dart';
import 'features/oobe/doc_page.dart';
import 'features/oobe/eggs.dart';
import 'features/oobe/update_page.dart';
import 'features/station/station_selector_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const RailGoApp(),
    ),
  );
}

// ───────────── Riverpod 装配 ─────────────

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final settingsProvider = Provider<SettingsStore>(
  (ref) => SharedPreferencesSettingsStore(ref.watch(sharedPrefsProvider)),
);

/// 防篡改时钟（状态机时间源；检测墙钟跳变自动重锚定）
final clockProvider = Provider<TrustworthyClock>((ref) => TrustworthyClock());

final apiClientProvider = Provider<RailGoApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  return RailGoApiClient(
    resolveBase: (code) => settings.serviceSource(code) ?? '',
    // WAF 合规（llms.txt 2026.08.08 限速）：全局令牌桶 2 rps / 突发 4
    bucket: TokenBucket(), // 默认即 2 rps / 突发 4（WAF 合规，见 rate_limiter.dart）
  );
});

final railGoApiProvider = Provider<RailGoApi>((ref) => RailGoApi(ref.watch(apiClientProvider)));

class RailGoApp extends ConsumerWidget {
  const RailGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Color(0xFF114598);
    return MaterialApp(
      title: 'RailGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        fontFamily: 'DIN1451',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        fontFamily: 'DIN1451',
      ),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        for (final e in DocAssetPage.kRoutes.entries)
          e.key: (_) => DocAssetPage(docAsset: e.value, fallbackText: kDocFallbacks[e.value] ?? ''),
        '/egg': (_) => const EggFireworksPage(),
        '/newyear': (_) => const NewYearPage(),
        '/aboutEgg': (_) => const AboutEggPage(),
        '/update': (_) => UpdatePage(api: _stubApi()),
        '/speed': (_) => const SpeedPage(),
        '/station/select': (_) => const SizedBox.shrink(), // 由HomePage以push方式打开（需ref注入）
      },
      home: const HomePage(),
    );
  }

  RailGoApi _stubApi() => RailGoApi(RailGoApiClient());
}
