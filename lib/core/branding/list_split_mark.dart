import 'package:flutter/material.dart';

/// Original shared-checklist mark. Geometry is also the source of the generated
/// Android vectors, SVG and legacy launcher PNGs (tools/branding).
class ListSplitMark extends StatelessWidget {
  const ListSplitMark({super.key, this.size = 192});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: CustomPaint(
          size: Size.square(size), painter: const ListSplitMarkPainter()));
}

class ListSplitMarkPainter extends CustomPainter {
  const ListSplitMarkPainter();
  static const foreground = Color(0xFFF4AE45);
  static const background = Color(0xFF202020);

  // Closed front list, open shared panel, one check and three readable strokes.
  static const paths = <List<List<double>>>[
    [
      [0, 33, 25],
      [1, 59, 25],
      [2, 65, 25, 65, 31],
      [1, 65, 72],
      [2, 65, 78, 59, 78],
      [1, 33, 78],
      [2, 27, 78, 27, 72],
      [1, 27, 31],
      [2, 27, 25, 33, 25]
    ],
    [
      [0, 73, 37],
      [1, 76, 37],
      [2, 82, 37, 82, 43],
      [1, 82, 72],
      [2, 82, 78, 76, 78],
      [1, 73, 78]
    ],
    [
      [0, 37, 41],
      [1, 42, 46],
      [1, 54, 35]
    ],
    [
      [0, 38, 57],
      [1, 54, 57]
    ],
    [
      [0, 38, 67],
      [1, 50, 67]
    ],
    [
      [0, 73, 51],
      [1, 75, 51]
    ],
    [
      [0, 73, 63],
      [1, 75, 63]
    ],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    final paint = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final commands in paths) {
      final path = Path();
      for (final c in commands) {
        switch (c[0].toInt()) {
          case 0:
            path.moveTo(c[1], c[2]);
          case 1:
            path.lineTo(c[1], c[2]);
          case 2:
            path.quadraticBezierTo(c[1], c[2], c[3], c[4]);
        }
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ListSplitMarkPainter oldDelegate) => false;
}
