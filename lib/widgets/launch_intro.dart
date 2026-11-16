import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import 'common.dart';

/// The opening screen: the popper on coral (same spot as the iPhone launch
/// screen), then the brush-lettered name and tagline. Shown for a moment
/// when the app starts; a tap skips it.
class LaunchIntro extends StatelessWidget {
  const LaunchIntro({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: HC.coral,
        child: Stack(
          children: [
            Center(child: Image.asset('assets/brand/popper.png', width: 120, height: 120)),
            Align(
              alignment: const Alignment(0, 0.34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandName(size: 60, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(
                    'Plan it. Play it. Party!',
                    style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
