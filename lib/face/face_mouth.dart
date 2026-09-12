import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';

/// Lips that part in sync with the audio level (0..1) while speaking.
/// If no level arrives (e.g. streamed URL audio), falls back to a steady flap.
class FaceMouth extends StatefulWidget {
  final FaceState faceState;
  final double screenWidth;
  final FaceColor faceColor;
  final ValueListenable<double>? level;

  const FaceMouth({
    super.key,
    required this.faceState,
    required this.screenWidth,
    required this.faceColor,
    this.level,
  });

  @override
  State<FaceMouth> createState() => _FaceMouthState();
}

class _FaceMouthState extends State<FaceMouth> with SingleTickerProviderStateMixin {
  late final AnimationController _clock; // free-running ticker, 1s loop
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    widget.level?.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(FaceMouth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level?.removeListener(_onLevel);
      widget.level?.addListener(_onLevel);
    }
  }

  void _onLevel() => _lastLevelAt = DateTime.now();

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    _clock.dispose();
    super.dispose();
  }

  double get _baseOpacity {
    switch (widget.faceState) {
      case FaceState.idle:
        return 0.6;
      case FaceState.listening:
      case FaceState.processing:
        return 0.8;
      case FaceState.speaking:
        return 1.0;
    }
  }

  double _openAmount() {
    if (widget.faceState != FaceState.speaking) return 0;
    final fresh = DateTime.now().difference(_lastLevelAt).inMilliseconds < 300;
    if (fresh) return widget.level!.value;
    // ponytail: no level source -> synthetic 5 Hz flap
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return 0.5 + 0.5 * math.sin(t * 2 * math.pi * 5);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.screenWidth * 0.50;
    final h = widget.screenWidth * 0.18;

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final open = _openAmount().clamp(0.0, 1.0);
        return Opacity(
          opacity: _baseOpacity,
          child: CustomPaint(
            size: Size(w, h),
            painter: _LipsPainter(
              color: widget.faceColor.color,
              open: open,
              glow: widget.faceState == FaceState.speaking ? 0.35 + 0.35 * open : 0.2,
            ),
          ),
        );
      },
    );
  }
}

class _LipsPainter extends CustomPainter {
  final Color color;
  final double open;
  final double glow;

  _LipsPainter({required this.color, required this.open, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final lip = size.height * 0.11; // lip thickness
    final gap = open * (size.height - lip * 2);
    final total = lip * 2 + gap;
    final top = (size.height - total) / 2;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, total),
      Radius.circular(total / 2),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..color = color.withOpacity(glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(outer, Paint()..color = color);

    if (gap < 4) return;
    final cavity = RRect.fromRectAndRadius(
      Rect.fromLTWH(lip * 1.5, top + lip, size.width - lip * 3, gap),
      Radius.circular(gap / 2),
    );
    canvas.drawRRect(cavity, Paint()..color = const Color(0xFF1A0A05));
    // Teeth
    final teeth = math.min(gap * 0.35, lip * 1.2);
    canvas.save();
    canvas.clipRRect(cavity);
    canvas.drawRect(
      Rect.fromLTWH(lip * 1.5, top + lip, size.width - lip * 3, teeth),
      Paint()..color = Colors.white.withOpacity(0.9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LipsPainter o) => o.open != open || o.color != color || o.glow != glow;
}
