// lib/features/oobe/eggs.dart
//
// 彩蛋页三件套（Phase 4 清单：pages/404/egg、pages/404/newYear、pages/about/egg 1:1 保留重构）
//   EggFireworksPage —— 烟花 + 打字机（原 404/egg.vue：由 search 计数触发）
//   NewYearPage     —— 新年 404：王安石《元日》+ B 站视频入口（原 404/newYear.vue）
//   AboutEggPage    —— 开发者长文彩蛋（原 about/egg.vue：Funnyegg）
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EggFireworksPage extends StatefulWidget {
  const EggFireworksPage({super.key, this.searchCount = 0});
  final int searchCount;

  @override
  State<EggFireworksPage> createState() => _EggFireworksPageState();
}

class _EggFireworksPageState extends State<EggFireworksPage> with SingleTickerProviderStateMixin {
  static const _palette = [0xFFFF1493, 0xFF00BFFF, 0xFFADFF2F, 0xFFFFD700, 0xFFFF4500, 0xFFFFFFFF, 0xFF00FFFF];
  static const _lines = [
    '你来到了没有轨道的荒原',
    '但探索永无止境',
    'RailGo 与你同行 🚄',
  ];

  late final AnimationController _ctrl;
  final List<_Spark> _sparks = [];
  Timer? _burstTimer;
  int _typedChars = 0;
  Timer? _typeTimer;

  String get _typedText {
    final full = _lines.join('\n');
    return full.substring(0, _typedChars.clamp(0, full.length));
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _burstTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _burst());
    _typeTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final full = _lines.join('\n');
      if (_typedChars < full.length) setState(() => _typedChars++);
    });
  }

  void _burst() {
    final rnd = math.Random();
    final color = _palette[rnd.nextInt(_palette.length)];
    final cx = rnd.nextDouble();
    final cy = rnd.nextDouble() * 0.6 + 0.1;
    for (var i = 0; i < 28; i++) {
      final angle = i / 28 * 2 * math.pi;
      _sparks.add(_Spark(origin: Offset(cx, cy), angle: angle, color: Color(color)));
    }
    if (_sparks.length > 420) _sparks.removeRange(0, _sparks.length - 420);
  }

  @override
  void dispose() {
    _burstTimer?.cancel();
    _typeTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _FireworksPainter(_sparks, _ctrl.value),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_typedText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.8)),
                    const SizedBox(height: 48),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回旅途'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Spark {
  _Spark({required this.origin, required this.angle, required this.color});
  final Offset origin;
  final double angle;
  final Color color;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.sparks, this.t);
  final List<_Spark> sparks;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.6..style = PaintingStyle.stroke;
    for (final s in sparks) {
      final progress = t;
      final dist = 30.0 + progress * 90;
      final o = Offset(s.origin.dx * size.width, s.origin.dy * size.height);
      final dir = Offset(math.cos(s.angle), math.sin(s.angle));
      final start = o + dir * dist;
      final end = o + dir * (dist + 14 * (1 - progress));
      paint.color = s.color.withAlpha((255 * (1 - progress).clamp(0.0, 1.0)).round()); // ohos 3.22 兼容
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => true;
}

class NewYearPage extends StatelessWidget {
  const NewYearPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(title: const Text('Error'), backgroundColor: const Color(0xFFB22222), foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('404', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Color(0xFF114598))),
          const SizedBox(height: 12),
          const Text('你来到了没有轨道的荒原\n但没关系，铁路行祝您新年快乐！',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFB22222))),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Column(
              children: [
                Text('“爆竹声中一岁除，\n春风送暖入屠苏。”',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.9)),
                SizedBox(height: 10),
                Text('— 王安石《元日》', style: TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            // 原 web-view B 站视频（BV1ad4y1V7wb）；Flutter 版经外链打开
            onPressed: () {}, // 由外层接 url_launcher / webview 时启用
            icon: const Icon(Icons.celebration_outlined),
            label: const Text('观看新年视频'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB22222)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EggFireworksPage()),
            ),
            child: const Text('彩蛋'),
          ),
        ],
      ),
    );
  }
}

class AboutEggPage extends StatelessWidget {
  const AboutEggPage({super.key});

  static const story = 'lxy同学握着她那台索尼A7S2站在教学楼二楼风雨长廊的门口……（原文见基线 pages/about/egg.vue，此处保留入口与 Funnyegg 语义）';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Die Verliebte von TKP30')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(story, style: TextStyle(fontSize: 14, height: 1.9)),
      ),
    );
  }
}
