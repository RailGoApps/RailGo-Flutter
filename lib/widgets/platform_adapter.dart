// lib/widgets/platform_adapter.dart
//
// 三端自适应外壳（任务书 §6.1）：
//   iOS        → Cupertino（CupertinoTabBar）
//   Android    → Material 3 Expressive（浮动底栏：大圆角 SurfaceContainer + FAB 舱位，
//                规格参照 md3e-skill：FlexibleBottomAppBar/FAB Menu/48+ 色彩角色）
//   HarmonyOS  → ArkUI 风格（胶囊分段导航）
// 交互动画遵循 apple-design 技能参数表（damping 1.0/response 0.4；sheet 0.8/0.3）。
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum UiFlavor { cupertino, material3e, arkui }

UiFlavor inferFlavor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return UiFlavor.cupertino;
    case TargetPlatform.android:
      return UiFlavor.material3e;
    default:
      return UiFlavor.arkui;
  }
}

/// Apple 弹簧参数（apple-design 技能：Move 1.0/0.4s；Drawer/Sheet 0.8/0.3s）
SpringDescription get kAppleSpringDefault => SpringDescription.withDampingRatio(
      mass: 1, // 必填；ratio 省略 = 默认 1.0（临界阻尼）
      stiffness: 400,
    );

SpringDescription get kAppleSpringSheet => SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 400,
      ratio: 0.8,
    );

class AdaptiveNavItem {
  const AdaptiveNavItem(
      {required this.label,
      required this.icon,
      required this.selectedIcon,
      required this.onTap});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onTap;
}

class AdaptiveBottomNav extends StatelessWidget {
  const AdaptiveBottomNav({
    super.key,
    required this.flavor,
    required this.items,
    required this.selectedIndex,
    this.fabIcon,
    this.onFab,
  });

  final UiFlavor flavor;
  final List<AdaptiveNavItem> items;
  final int selectedIndex;
  final IconData? fabIcon;
  final VoidCallback? onFab;

  @override
  Widget build(BuildContext context) {
    return switch (flavor) {
      UiFlavor.material3e => _md3eFloatingBar(context),
      UiFlavor.cupertino => _cupertinoTabBar(context),
      UiFlavor.arkui => _arkuiPillNav(context),
    };
  }

  // ── Material 3 Expressive：浮动底栏（大圆角 + FAB 舱位） ──
  Widget _md3eFloatingBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Material(
              elevation: 3,
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(28), // MD3E 大圆角
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _md3eItem(context, items[i], i == selectedIndex),
                  ],
                ),
              ),
            ),
          ),
          if (fabIcon != null && onFab != null) ...[
            const SizedBox(width: 12),
            FloatingActionButton.large(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              shape: const CircleBorder(),
              onPressed: onFab,
              child: Icon(fabIcon),
            ),
          ],
        ],
      ),
    );
  }

  Widget _md3eItem(BuildContext context, AdaptiveNavItem item, bool selected) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: ShapeDecoration(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: const StadiumBorder(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.selectedIcon : item.icon,
                color: color, size: 22),
            const SizedBox(height: 2),
            Text(item.label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ── iOS：CupertinoTabBar ──
  Widget _cupertinoTabBar(BuildContext context) {
    return CupertinoTabBar(
      items: [
        for (final item in items)
          BottomNavigationBarItem(
            icon: Icon(item.icon),
            activeIcon: Icon(item.selectedIcon),
            label: item.label,
          ),
      ],
      currentIndex: selectedIndex.clamp(0, items.length - 1),
      onTap: (i) => items[i].onTap(),
    );
  }

  // ── HarmonyOS：ArkUI 胶囊导航 ──
  Widget _arkuiPillNav(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Material(
        color: cs.surfaceContainerHighest
            .withAlpha(230), // withAlpha: 3.22 存在 / 3.27 未废弃（ohos 工具链兼容）
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _arkuiItem(cs, items[i], i == selectedIndex),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arkuiItem(ColorScheme cs, AdaptiveNavItem item, bool selected) {
    return GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: ShapeDecoration(
          color: selected ? cs.primary : Colors.transparent,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.selectedIcon : item.icon,
                size: 18, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(item.label,
                  style: TextStyle(fontSize: 13, color: cs.onPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 平台主题：品牌色种子（基线 #114598）
Color brandSeed(BuildContext context) => const Color(0xFF114598);

double? lerpDoubleOrNull(double a, double b, double t) => lerpDouble(a, b, t);
