import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import 'theme.dart';

/// Live download/upload area chart on one shared rate axis, with a
/// crosshair + tooltip on hover (desktop) or drag (touch).
class TrafficChart extends StatefulWidget {
  const TrafficChart({super.key, required this.samples, required this.window, required this.bits});
  final List<Sample> samples;
  final Duration window;
  final bool bits;

  @override
  State<TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<TrafficChart> {
  double? _hoverX;

  void _hover(double? x) => setState(() => _hoverX = x);

  @override
  Widget build(BuildContext context) {
    final viz = Viz.of(context);
    final now = widget.samples.isEmpty ? DateTime.now() : widget.samples.last.at;
    final from = now.subtract(widget.window);
    final pts = widget.samples.where((s) => s.at.isAfter(from)).toList();

    return SizedBox(
      height: 220,
      child: LayoutBuilder(
        builder: (context, box) {
          final geo = _Geometry(box.biggest, now, widget.window);
          Sample? hit;
          if (_hoverX != null && pts.isNotEmpty) {
            hit = pts.reduce((a, b) => (geo.x(a.at) - _hoverX!).abs() < (geo.x(b.at) - _hoverX!).abs() ? a : b);
          }
          final tipLeft = hit == null ? 0.0 : (geo.x(hit.at) + 12).clamp(0.0, max(0.0, box.maxWidth - 172)).toDouble();
          final t = Theme.of(context).textTheme;
          return MouseRegion(
            onHover: (e) => _hover(e.localPosition.dx),
            onExit: (_) => _hover(null),
            child: GestureDetector(
              onHorizontalDragStart: (e) => _hover(e.localPosition.dx),
              onHorizontalDragUpdate: (e) => _hover(e.localPosition.dx),
              onHorizontalDragEnd: (_) => _hover(null),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ChartPainter(pts, geo, widget.bits, viz, t.labelSmall!.copyWith(color: viz.ink), hit),
                    ),
                  ),
                  if (pts.length < 2)
                    Center(
                      child: Text('Collecting samples…', style: t.bodyMedium?.copyWith(color: viz.ink)),
                    ),
                  if (hit != null)
                    Positioned(
                      left: tipLeft,
                      top: 4,
                      width: 160,
                      child: IgnorePointer(
                        child: Card(
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: DefaultTextStyle(
                              style: t.bodySmall!.copyWith(fontFeatures: tabular),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fmtClock(hit.at), style: t.labelMedium),
                                  const SizedBox(height: 4),
                                  _tipRow(viz.down, 'Down', fmtRate(hit.down, bits: widget.bits)),
                                  _tipRow(viz.up, 'Up', fmtRate(hit.up, bits: widget.bits)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tipRow(Color c, String label, String value) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label),
      const Spacer(),
      Text(value),
    ],
  );
}

class _Geometry {
  _Geometry(this.size, this.now, this.window);
  static const axisW = 72.0, padTop = 8.0, padBottom = 8.0;
  final Size size;
  final DateTime now;
  final Duration window;

  double get plotW => size.width - axisW;
  double get plotH => size.height - padTop - padBottom;
  double x(DateTime t) => plotW * (1 - now.difference(t).inMicroseconds / window.inMicroseconds);
}

double _niceCeil(double v) {
  final e = pow(10, (log(v) / ln10).floor()).toDouble();
  final f = v / e;
  return (f <= 1
          ? 1
          : f <= 2
          ? 2
          : f <= 5
          ? 5
          : 10) *
      e;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.pts, this.geo, this.bits, this.viz, this.labelStyle, this.hit);
  final List<Sample> pts;
  final _Geometry geo;
  final bool bits;
  final Viz viz;
  final TextStyle labelStyle;
  final Sample? hit;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = bits ? 8.0 : 1.0;
    final peak = pts.fold<double>(0, (m, s) => max(m, max(s.down, s.up)));
    // Nice top in display units, floored at 1 KB/s (8 Kbps) so idle links don't amplify noise.
    final top = _niceCeil(max(peak * unit, 1000 * unit)) / unit;
    double y(double v) => _Geometry.padTop + geo.plotH * (1 - v / top);

    final grid = Paint()
      ..color = viz.grid
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final yy = y(top * f);
      canvas.drawLine(Offset(0, yy), Offset(geo.plotW, yy), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: fmtRate(top * f, bits: bits),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _Geometry.axisW - 8);
      tp.paint(canvas, Offset(geo.plotW + 8, yy - tp.height / 2));
    }

    if (pts.length >= 2) {
      final base = y(0);
      for (final (value, color, alpha) in [((Sample s) => s.down, viz.down, .16), ((Sample s) => s.up, viz.up, .10)]) {
        final line = Path()..moveTo(geo.x(pts.first.at), y(value(pts.first)));
        for (final s in pts.skip(1)) {
          line.lineTo(geo.x(s.at), y(value(s)));
        }
        final fill = Path.from(line)
          ..lineTo(geo.x(pts.last.at), base)
          ..lineTo(geo.x(pts.first.at), base)
          ..close();
        canvas.drawPath(fill, Paint()..color = color.withValues(alpha: alpha));
        canvas.drawPath(
          line,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final h = hit;
    if (h != null) {
      final x = geo.x(h.at);
      canvas.drawLine(Offset(x, _Geometry.padTop), Offset(x, y(0)), Paint()..color = viz.ink.withValues(alpha: .5));
      for (final (v, c) in [(h.down, viz.down), (h.up, viz.up)]) {
        canvas.drawCircle(Offset(x, y(v)), 6, Paint()..color = viz.surface);
        canvas.drawCircle(Offset(x, y(v)), 4, Paint()..color = c);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
