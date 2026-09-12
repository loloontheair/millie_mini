import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Orange hard hat drawn above the eyes (store-associate look).
class HardHat extends StatelessWidget {
  final double screenWidth;

  const HardHat({super.key, required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final w = screenWidth * 0.78;
    final h = w * 0.42;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(w, h), painter: _HardHatPainter()),
          // Brand badge on the dome (asset shipped in the repo)
          Positioned(
            top: h * 0.22,
            child: Image.asset(
              'assets/icon/home_depot.png',
              width: w * 0.22,
              height: w * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HardHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const orange = AppColors.homeDepotOrange;

    // Brim
    final brim = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.82, w, h * 0.18),
      Radius.circular(h * 0.09),
    );
    canvas.drawRRect(brim, Paint()..color = const Color(0xFFD95300));

    // Dome
    final dome = Path()
      ..moveTo(w * 0.1, h * 0.86)
      ..cubicTo(w * 0.1, -h * 0.15, w * 0.9, -h * 0.15, w * 0.9, h * 0.86)
      ..close();
    canvas.drawPath(dome, Paint()..color = orange);

    // Center ridge highlight
    final ridge = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.44, h * 0.05, w * 0.12, h * 0.78),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(ridge, Paint()..color = Colors.white.withOpacity(0.28));
  }

  @override
  bool shouldRepaint(_HardHatPainter oldDelegate) => false;
}
