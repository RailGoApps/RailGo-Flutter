// lib/features/train/route_map.dart
//
// 列车运行线路点承接组件（Phase 4 清单第 5 项）：
//   基线承接物为自研天地图组件（siji-tianditu，OpenLayers 0 引用——Baseline §0/#2）。
//   Flutter 版第一期为"无第三方依赖的自绘线路图"（CustomPaint + WGS-84 投影归一化），
//   与基线同样支持多段线路（交路段按 index 排序）与站点标记；
//   瓦片地图（flutter_map + 天地图图层）列为后续增强，不阻塞承接。
library;

import 'package:flutter/material.dart';

import '../../core/utils/coord_transform.dart';

class RouteLineMapView extends StatelessWidget {
  const RouteLineMapView({super.key, required this.data, this.height = 320});

  final MapLineData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        color: cs.surfaceContainerLowest,
        child: InteractiveViewer(
          maxScale: 6,
          child: CustomPaint(
            painter: _RouteLinePainter(data: data, primary: cs.primary, onPrimary: cs.onPrimary),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  _RouteLinePainter({required this.data, required this.primary, required this.onPrimary});
  final MapLineData data;
  final Color primary;
  final Color onPrimary;

  @override
  void paint(Canvas canvas, Size size) {
    final b = mapLineBounds(data);
    Offset p(double lng, double lat) {
      final (nx, ny) = projectNormalized(lng, lat, b.minLng, b.maxLng, b.minLat, b.maxLat);
      return Offset(nx * size.width, ny * size.height);
    }

    // 线路段（多段时逐段偏移绘制，模拟复线）
    final linePaint = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < data.segments.length; i++) {
      final seg = data.segments[i];
      final offset = (i - (data.segments.length - 1) / 2) * 4.0;
      final path = Path();
      var first = true;
      for (final pt in seg.line) {
        final o = p(pt.lng, pt.lat) + Offset(0, offset);
        if (first) {
          path.moveTo(o.dx, o.dy);
          first = false;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // 站点标记
    final dotPaint = Paint()..color = primary;
    final dotBorder = Paint()..color = onPrimary..style = PaintingStyle.stroke..strokeWidth = 2;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final s in data.stations) {
      final o = p(s.lng, s.lat);
      canvas.drawCircle(o, 5, dotPaint);
      canvas.drawCircle(o, 5, dotBorder);
      tp.text = TextSpan(
        text: s.name,
        style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600),
      );
      tp.layout();
      tp.paint(canvas, o + const Offset(7, -tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RouteLinePainter oldDelegate) => oldDelegate.data != data;
}
